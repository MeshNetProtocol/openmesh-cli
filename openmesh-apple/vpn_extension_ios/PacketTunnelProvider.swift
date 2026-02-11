//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/16.
//

import NetworkExtension
import OpenMeshGo
import Foundation
import Darwin
import VPNLibrary

// Match sing-box structure: PacketTunnelProvider is a thin subclass; logic lives in ExtensionProvider.
class ExtensionProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var boxService: OMLibboxBoxService?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?
    private var sharedDataDirURL: URL?
    private var cacheDirURL: URL?

    private let serviceQueue = DispatchQueue(label: "com.meshflux.vpn.service", qos: .userInitiated)
    private var rulesWatcher: FileSystemWatcher?
    private var pendingReload: DispatchWorkItem?
    private var lastRuntimeDiagFingerprint: Data?
    private let memoryLogQueue = DispatchQueue(label: "com.meshflux.vpn.memory")
    private var memoryLogTimer: DispatchSourceTimer?

    private func prepareBaseDirectories(fileManager: FileManager) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        // Align with VPNLibrary/FilePath: use App Group as the shared root.
        guard let sharedDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName) else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container. Check Signing & Capabilities (App Groups) for both the app and the extension."])
        }
        let baseDirURL = sharedDir
        let cacheDirURL = FilePath.cacheDirectory
        let workingDirURL = FilePath.workingDirectory
        let sharedDataDirURL = baseDirURL.appendingPathComponent("MeshFlux", isDirectory: true)

        // Keep the UNIX socket path within Darwin's `sockaddr_un.sun_path` limit (~104 bytes incl NUL).
        let commandSocketPath = baseDirURL.appendingPathComponent("command.sock", isDirectory: false).path
        let socketBytes = commandSocketPath.utf8.count
        if socketBytes > 103 {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "command.sock path too long (\(socketBytes) bytes): \(commandSocketPath)"])
        }

        try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sharedDataDirURL, withIntermediateDirectories: true)

        cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)
        self.sharedDataDirURL = sharedDataDirURL
        self.cacheDirURL = cacheDirURL
        return (
            baseDirURL: baseDirURL,
            basePath: baseDirURL.path,
            workingPath: workingDirURL.path,
            tempPath: cacheDirURL.path
        )
    }

    private func cleanupStaleCommandSocket(in baseDirURL: URL, fileManager: FileManager) {
        let commandSocketURL = baseDirURL.appendingPathComponent("command.sock", isDirectory: false)
        if fileManager.fileExists(atPath: commandSocketURL.path) {
            try? fileManager.removeItem(at: commandSocketURL)
        }
    }

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("MeshFlux VPN extension startTunnel begin")
        startMemoryLogging()
        logMemorySnapshot(tag: "startTunnel_begin")

        // Keep the provider method fast/non-blocking: run the blocking libbox startup on a background queue.
        serviceQueue.async {
            var err: NSError?
            do {
                let fileManager = FileManager.default
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager)
                let baseDirURL = prepared.baseDirURL
                let basePath = prepared.basePath
                let workingPath = prepared.workingPath
                let tempPath = prepared.tempPath

                self.baseDirURL = baseDirURL
                NSLog("MeshFlux VPN extension baseDirURL=%@", baseDirURL.path)

                let setup = OMLibboxSetupOptions()
                setup.basePath = basePath
                setup.workingPath = workingPath
                setup.tempPath = tempPath
                guard OMLibboxSetup(setup, &err) else {
                    throw err ?? NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
                }
                // Align with SFI: enable libbox memory limiter on iOS by default
                // (unless user explicitly disables it in shared preferences).
                OMLibboxSetMemoryLimit(!SharedPreferences.ignoreMemoryLimit.getBlocking())

                // Capture Go/libbox stderr to a file inside the App Group cache directory (helps debugging panics).
                let stderrLogPath = (baseDirURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Caches", isDirectory: true)
                    .appendingPathComponent("stderr.log", isDirectory: false)).path
                _ = OMLibboxRedirectStderr(stderrLogPath, &err)
                err = nil

                let platform = OpenMeshLibboxPlatformInterface(self)
                let server = OMLibboxNewCommandServer(platform, 2000)
                guard let server else {
                    throw NSError(domain: "com.meshflux", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
                }

                self.platformInterface = platform
                self.commandServer = server

                let configContent = try self.resolveConfigContent()
                NSLog("MeshFlux VPN extension: passing config to libbox. stderr.log: %@", stderrLogPath)
                var serviceErr: NSError?
                guard let boxService = OMLibboxNewService(configContent, platform, &serviceErr) else {
                    throw serviceErr ?? NSError(domain: "com.meshflux", code: 4, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewService failed"])
                }
                server.setService(boxService)
                self.boxService = boxService
                try server.start()
                NSLog("MeshFlux VPN extension command server started")

                try boxService.start()
                NSLog("MeshFlux VPN extension box service started (openTun / setTunnelNetworkSettings done)")

                try self.startRulesWatcherIfNeeded()
                self.logMemorySnapshot(tag: "startTunnel_ready")

                NSLog("MeshFlux VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("MeshFlux VPN extension startTunnel failed: %@", String(describing: error))
                self.logMemorySnapshot(tag: "startTunnel_failed")
                self.stopMemoryLogging()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logMemorySnapshot(tag: "stopTunnel_begin")
        serviceQueue.async {
            self.rulesWatcher?.cancel()
            self.rulesWatcher = nil
            self.pendingReload?.cancel()
            self.pendingReload = nil

            try? self.boxService?.close()
            try? self.commandServer?.close()
            self.boxService = nil
            self.commandServer = nil
            self.platformInterface?.reset()
            self.platformInterface = nil
            if let baseDirURL = self.baseDirURL {
                self.cleanupStaleCommandSocket(in: baseDirURL, fileManager: .default)
            }
            self.logMemorySnapshot(tag: "stopTunnel_end")
            self.stopMemoryLogging()
            completionHandler()
        }
    }

    private func startMemoryLogging() {
        guard memoryLogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: memoryLogQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.logMemorySnapshot(tag: "periodic")
        }
        timer.resume()
        memoryLogTimer = timer
    }

    private func stopMemoryLogging() {
        memoryLogTimer?.cancel()
        memoryLogTimer = nil
    }

    private func logMemorySnapshot(tag: String) {
        let footprint = currentPhysicalFootprintMB()
        if footprint > 0 {
            NSLog("MeshFlux VPN extension memory tag=%@ phys_footprint_mb=%.1f", tag, footprint)
        } else {
            NSLog("MeshFlux VPN extension memory tag=%@ phys_footprint_mb=unknown", tag)
        }
    }

    private func currentPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        serviceQueue.async {
            let response = self.handleAppMessage0(messageData)
            completionHandler?(response)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {}

    // MARK: - Config resolution (profile-driven only)

    /// Resolves config strictly from the selected profile.
    /// Raw profile mode: do not rewrite route/dns by app mode.
    private func resolveConfigContent() throws -> String {
        let profileID = SharedPreferences.selectedProfileID.getBlocking()
        guard profileID >= 0, let profile = try? ProfileManager.getBlocking(profileID) else {
            throw NSError(
                domain: "com.meshflux",
                code: 3004,
                userInfo: [NSLocalizedDescriptionKey: "No selected profile. VPN start aborted by strict profile-only mode."]
            )
        }
        let profileToProvider = SharedPreferences.installedProviderIDByProfile.getBlocking()
        let providerID = profileToProvider[String(profileID)]
        let content = try profile.read()
        NSLog("MeshFlux VPN extension using profile-driven config (id=%lld, name=%@)", profileID, profile.name)
        let withRules = applyDynamicRoutingRulesToConfigContent(content)
        let effectiveContent = applyRoutingModeToConfigContent(withRules, isGlobalMode: false)
        writeRuntimeDiagnostics(
            profileID: profileID,
            profileName: profile.name,
            profilePath: profile.path,
            providerID: providerID,
            rawConfigContent: content,
            effectiveConfigContent: effectiveContent
        )
        return effectiveContent
    }

    private func writeRuntimeDiagnostics(
        profileID: Int64,
        profileName: String,
        profilePath: String,
        providerID: String?,
        rawConfigContent: String,
        effectiveConfigContent: String
    ) {
        guard let sharedDataDirURL else { return }
        let fileManager = FileManager.default

        let routingRulesURL = providerID.map { FilePath.providerRoutingRulesFile(providerID: $0) }
        let routingRulesPath = routingRulesURL?.path ?? ""
        let routingRulesExists = routingRulesURL.map { fileManager.fileExists(atPath: $0.path) } ?? false

        let rawSummary = configSummary(from: rawConfigContent)
        let effectiveSummary = configSummary(from: effectiveConfigContent)
        let diagURL = sharedDataDirURL.appendingPathComponent("vpn_runtime_diag.json", isDirectory: false)

        do {
            let fingerprintObject: [String: Any] = [
                "profile_id": profileID,
                "profile_name": profileName,
                "profile_path": profilePath,
                "provider_id": providerID ?? "",
                "provider_routing_rules_path": routingRulesPath,
                "provider_routing_rules_exists": routingRulesExists,
                "raw": rawSummary,
                "effective": effectiveSummary,
            ]
            let fingerprintData = try JSONSerialization.data(withJSONObject: fingerprintObject, options: [.sortedKeys])
            if let lastRuntimeDiagFingerprint,
               lastRuntimeDiagFingerprint == fingerprintData,
               fileManager.fileExists(atPath: diagURL.path) {
                return
            }

            var diag: [String: Any] = [:]
            diag["timestamp"] = ISO8601DateFormatter().string(from: Date())
            diag["profile_id"] = profileID
            diag["profile_name"] = profileName
            diag["profile_path"] = profilePath
            diag["provider_id"] = providerID ?? ""
            diag["provider_routing_rules_path"] = routingRulesPath
            diag["provider_routing_rules_exists"] = routingRulesExists
            diag["raw"] = rawSummary
            diag["effective"] = effectiveSummary

            try fileManager.createDirectory(at: sharedDataDirURL, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: diag, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: diagURL, options: [.atomic])
            lastRuntimeDiagFingerprint = fingerprintData
            let finalOutbound = (effectiveSummary["route_final"] as? String) ?? "nil"
            NSLog(
                "MeshFlux VPN extension wrote runtime diag: %@ (provider=%@ route.final=%@)",
                diagURL.path,
                providerID ?? "",
                finalOutbound
            )
            if let line = "MeshFlux VPN runtime diag: \(diagURL.path) provider=\(providerID ?? "") route_final=\(finalOutbound)\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
        } catch {
            NSLog("MeshFlux VPN extension write runtime diag failed: %@", String(describing: error))
            if let line = "MeshFlux VPN runtime diag write failed: \(String(describing: error))\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
        }
    }

    private func configSummary(from content: String) -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
            return ["parse_ok": false]
        }

        var summary: [String: Any] = ["parse_ok": true]

        if let route = obj["route"] as? [String: Any] {
            summary["route_final"] = (route["final"] as? String) ?? ""
            if let ruleSets = route["rule_set"] as? [Any] {
                let remoteTags = ruleSets.compactMap { any -> String? in
                    guard let rs = any as? [String: Any] else { return nil }
                    guard (rs["type"] as? String) == "remote" else { return nil }
                    return rs["tag"] as? String
                }
                summary["remote_rule_set_tags"] = remoteTags.sorted()
                summary["remote_rule_set_count"] = remoteTags.count
            } else {
                summary["remote_rule_set_tags"] = [String]()
                summary["remote_rule_set_count"] = 0
            }
        } else {
            summary["route_final"] = ""
            summary["remote_rule_set_tags"] = [String]()
            summary["remote_rule_set_count"] = 0
        }

        if let dns = obj["dns"] as? [String: Any] {
            summary["dns_final"] = (dns["final"] as? String) ?? ""
        } else {
            summary["dns_final"] = ""
        }

        var outboundTags: [String] = []
        var selectorDefaults: [String: String] = [:]
        if let outbounds = obj["outbounds"] as? [Any] {
            for any in outbounds {
                guard let outbound = any as? [String: Any] else { continue }
                guard let tag = outbound["tag"] as? String, !tag.isEmpty else { continue }
                outboundTags.append(tag)
                if (outbound["type"] as? String)?.lowercased() == "selector" {
                    selectorDefaults[tag] = (outbound["default"] as? String) ?? ""
                }
            }
        }
        summary["outbound_tags"] = outboundTags.sorted()
        summary["selector_defaults"] = selectorDefaults

        if let inbounds = obj["inbounds"] as? [Any] {
            let tunStacks = inbounds.compactMap { any -> String? in
                guard let inbound = any as? [String: Any] else { return nil }
                guard (inbound["type"] as? String) == "tun" else { return nil }
                return (inbound["stack"] as? String) ?? ""
            }
            summary["tun_stacks"] = tunStacks
        } else {
            summary["tun_stacks"] = [String]()
        }

        return summary
    }

    // MARK: - Dynamic routing rules injection (routing_rules.json)

    /// Injects force-proxy rules from routing_rules.json immediately after sniff,
    /// so they have higher priority than geosite/geoip direct rules.
    private func applyDynamicRoutingRulesToConfigContent(_ content: String) -> String {
        guard let sharedDataDirURL else { return content }

        do {
            let profileID = SharedPreferences.selectedProfileID.getBlocking()
            let profileToProvider = SharedPreferences.installedProviderIDByProfile.getBlocking()
            let providerID = profileToProvider[String(profileID)]
            let overridingRulesURL: URL? = providerID.map { FilePath.providerRoutingRulesFile(providerID: $0) }

            let loaded = try DynamicRoutingRules.load(from: sharedDataDirURL, overridingJSONURL: overridingRulesURL)
            var rules = loaded.rules
            rules.normalize()

            guard var obj = parseConfigObjectRelaxed(content) else {
                if let line = "MeshFlux iOS VPN extension: inject routing_rules skipped (config parse failed)\n".data(using: .utf8) {
                    FileHandle.standardError.write(line)
                }
                return content
            }
            var route = (obj["route"] as? [String: Any]) ?? [:]
            var routeRules: [[String: Any]] = []
            if let existing = route["rules"] as? [Any] {
                routeRules = existing.compactMap { $0 as? [String: Any] }
            }

            func canonicalRule(_ rule: [String: Any]) -> String {
                var candidate = rule
                for key in ["ip_cidr", "domain", "domain_suffix", "domain_regex"] {
                    if let arr = candidate[key] as? [String] {
                        candidate[key] = arr.sorted()
                    } else if let arr = candidate[key] as? [Any] {
                        candidate[key] = arr.compactMap { $0 as? String }.sorted()
                    }
                }
                let data = (try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])) ?? Data()
                return String(decoding: data, as: UTF8.self)
            }

            var sniffIndex: Int? = nil
            for (index, rule) in routeRules.enumerated() {
                if (rule["action"] as? String) == "sniff" {
                    sniffIndex = index
                    break
                }
            }
            if sniffIndex == nil {
                routeRules.insert(["action": "sniff"], at: 0)
                sniffIndex = 0
            }

            let injected = rules.toSingBoxRouteRules(outboundTag: "proxy")
            let managedCanonicals = Set(injected.map(canonicalRule))
            routeRules.removeAll { managedCanonicals.contains(canonicalRule($0)) }

            let insertIndex = (sniffIndex ?? 0) + 1
            routeRules.insert(contentsOf: injected, at: insertIndex)

            route["rules"] = routeRules
            obj["route"] = route

            let output = try JSONSerialization.data(withJSONObject: obj, options: [])
            let source = loaded.sourceURL?.path ?? "(none)"
            let finalOutbound = (route["final"] as? String) ?? "nil"
            NSLog(
                "MeshFlux iOS VPN extension: injected routing_rules (%d proxy rules) from %@, route.final=%@",
                injected.count,
                source,
                finalOutbound
            )
            if let line = "MeshFlux iOS VPN extension: injected routing_rules count=\(injected.count) source=\(source) route_final=\(finalOutbound)\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
            return String(decoding: output, as: UTF8.self)
        } catch {
            NSLog("MeshFlux iOS VPN extension: inject routing_rules failed: %@", String(describing: error))
            if let line = "MeshFlux iOS VPN extension: inject routing_rules failed: \(String(describing: error))\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
            return content
        }
    }

    /// Accept JSONC/JSON5-ish profile content by stripping comments/trailing commas before parsing.
    private func parseConfigObjectRelaxed(_ content: String) -> [String: Any]? {
        guard let cleaned = stripJSONCommentsAndTrailingCommas(content) else { return nil }
        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return obj as? [String: Any]
    }

    private func stripJSONCommentsAndTrailingCommas(_ value: String) -> String? {
        let chars = Array(value.unicodeScalars)
        var out: [UnicodeScalar] = []
        out.reserveCapacity(chars.count)

        var index = 0
        var inString = false
        var escape = false

        func peek(_ offset: Int) -> UnicodeScalar? {
            let target = index + offset
            if target < 0 || target >= chars.count { return nil }
            return chars[target]
        }

        while index < chars.count {
            let c = chars[index]
            if inString {
                out.append(c)
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                index += 1
                continue
            }

            if c == "\"" {
                inString = true
                out.append(c)
                index += 1
                continue
            }

            if c == "/", let next = peek(1) {
                if next == "/" {
                    index += 2
                    while index < chars.count, chars[index] != "\n" { index += 1 }
                    continue
                }
                if next == "*" {
                    index += 2
                    while index + 1 < chars.count {
                        if chars[index] == "*" && chars[index + 1] == "/" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                    continue
                }
            }

            out.append(c)
            index += 1
        }

        let stripped = String(String.UnicodeScalarView(out))
        let chars2 = Array(stripped.unicodeScalars)
        var out2: [UnicodeScalar] = []
        out2.reserveCapacity(chars2.count)

        index = 0
        inString = false
        escape = false

        func nextNonWhitespace(from start: Int) -> UnicodeScalar? {
            var cursor = start
            while cursor < chars2.count {
                let c = chars2[cursor]
                if c != " " && c != "\t" && c != "\n" && c != "\r" { return c }
                cursor += 1
            }
            return nil
        }

        while index < chars2.count {
            let c = chars2[index]
            if inString {
                out2.append(c)
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if c == "\"" {
                inString = true
                out2.append(c)
                index += 1
                continue
            }
            if c == "," {
                if let next = nextNonWhitespace(from: index + 1), (next == "]" || next == "}") {
                    index += 1
                    continue
                }
            }
            out2.append(c)
            index += 1
        }

        return String(String.UnicodeScalarView(out2))
    }

    private func startRulesWatcherIfNeeded() throws {
        guard rulesWatcher == nil else { return }
        let providersDirURL = FilePath.providersDirectory
        try FileManager.default.createDirectory(at: providersDirURL, withIntermediateDirectories: true)
        let watcher = FileSystemWatcher(url: providersDirURL, queue: serviceQueue) { [weak self] in
            self?.scheduleReload(reason: "fs")
        }
        try watcher.start()
        rulesWatcher = watcher
        NSLog("MeshFlux VPN extension rules watcher started: %@", providersDirURL.path)
    }

    private func scheduleReload(reason: String) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadService(reason: reason)
        }
        pendingReload = work
        serviceQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reloadService(reason: String) {
        guard let commandServer, let platform = platformInterface else { return }
        do {
            let content = try resolveConfigContent()
            NSLog("MeshFlux VPN extension reloadService(%@) begin", reason)
            var serviceErr: NSError?
            guard let newService = OMLibboxNewService(content, platform, &serviceErr) else {
                NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: serviceErr))
                return
            }
            commandServer.setService(newService)
            try? boxService?.close()
            boxService = newService
            NSLog("MeshFlux VPN extension reloadService(%@) done", reason)
        } catch {
            NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: error))
        }
    }

    private func handleAppMessage0(_ messageData: Data) -> Data? {
        // Expected JSON:
        // {"action":"reload"}
        // {"action":"update_rules","format":"json"|"txt","content":"..."}
        do {
            let obj = try JSONSerialization.jsonObject(with: messageData, options: [.fragmentsAllowed])
            guard let dict = obj as? [String: Any], let action = dict["action"] as? String else {
                return messageData
            }

            switch action {
            case "reload":
                scheduleReload(reason: "app")
                return #"{"ok":true}"#.data(using: .utf8)
            case "update_rules":
                guard let format = dict["format"] as? String, let content = dict["content"] as? String else {
                    return #"{"ok":false,"error":"missing format/content"}"#.data(using: .utf8)
                }
                let profileID = SharedPreferences.selectedProfileID.getBlocking()
                let profileToProvider = SharedPreferences.installedProviderIDByProfile.getBlocking()
                guard let providerID = profileToProvider[String(profileID)], !providerID.isEmpty else {
                    return #"{"ok":false,"error":"no_selected_provider"}"#.data(using: .utf8)
                }
                let jsonURL = FilePath.providerRoutingRulesFile(providerID: providerID)
                switch format.lowercased() {
                case "json":
                    try FileManager.default.createDirectory(
                        at: jsonURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try content.data(using: .utf8)?.write(to: jsonURL, options: [.atomic])
                default:
                    return #"{"ok":false,"error":"unsupported format"}"#.data(using: .utf8)
                }
                scheduleReload(reason: "app_update_rules")
                return #"{"ok":true}"#.data(using: .utf8)
            default:
                return messageData
            }
        } catch {
            return messageData
        }
    }
}

final class PacketTunnelProvider: ExtensionProvider {}
