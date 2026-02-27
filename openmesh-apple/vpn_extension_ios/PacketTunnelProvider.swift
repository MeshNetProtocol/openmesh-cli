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

    private func injectFakeNodeForSingleNodeGroups(_ content: String) -> String {
        guard var config = parseConfigObjectRelaxed(content),
              var outbounds = config["outbounds"] as? [[String: Any]] else {
            return content
        }

        var needsFakeNode = false
        for i in 0..<outbounds.count {
            guard let type = outbounds[i]["type"] as? String else { continue }
            let t = type.lowercased()
            if t == "selector" || t == "urltest" {
                if var subOutbounds = outbounds[i]["outbounds"] as? [String], subOutbounds.count == 1 {
                    subOutbounds.append("fake-node-for-testing")
                    outbounds[i]["outbounds"] = subOutbounds
                    needsFakeNode = true
                } else if var subOutboundsAny = outbounds[i]["outbounds"] as? [Any], subOutboundsAny.count == 1 {
                    subOutboundsAny.append("fake-node-for-testing")
                    outbounds[i]["outbounds"] = subOutboundsAny
                    needsFakeNode = true
                }
                if needsFakeNode, let tag = outbounds[i]["tag"] as? String {
                    NSLog("MeshFlux VPN extension: Injected fake node into group '%@'", tag)
                }
            }
        }

        if needsFakeNode {
            NSLog("MeshFlux VPN extension: Added 'fake-node-for-testing' outbound to config")
            let fakeNode: [String: Any] = [
                "type": "shadowsocks",
                "tag": "fake-node-for-testing",
                "server": "127.0.0.1",
                "server_port": 65535,
                "password": "fake",
                "method": "aes-128-gcm"
            ]
            outbounds.append(fakeNode)
            config["outbounds"] = outbounds
            guard let patched = try? JSONSerialization.data(withJSONObject: config, options: []) else { return content }
            let str = String(data: patched, encoding: .utf8) ?? content
            return str
        }
        return content
    }

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
        let withFakeNode = injectFakeNodeForSingleNodeGroups(withRules)
        // Note: applyRoutingModeToConfigContent removed to align with sing-box upstream.
        // Configuration correctness is now fully delegated to the profile source.
        
        writeRuntimeDiagnostics(
            profileID: profileID,
            profileName: profile.name,
            profilePath: profile.path,
            providerID: providerID,
            rawConfigContent: content,
            effectiveConfigContent: withFakeNode
        )
        return withFakeNode
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

    private func pickPreferredURLTestGroupTag(timeoutSeconds: TimeInterval) throws -> String {
        let tags = try snapshotOutboundGroupTags(timeoutSeconds: timeoutSeconds)
        guard !tags.isEmpty else {
            throw NSError(domain: "com.meshflux", code: 5199, userInfo: [NSLocalizedDescriptionKey: "no outbound groups available"])
        }

        for preferred in ["proxy", "auto"] {
            if let match = tags.first(where: { $0.lowercased() == preferred }) {
                return match
            }
        }
        return tags[0]
    }

    private func snapshotOutboundGroupTags(timeoutSeconds: TimeInterval) throws -> [String] {
        guard boxService != nil else {
            throw NSError(domain: "com.meshflux", code: 5198, userInfo: [NSLocalizedDescriptionKey: "service not running"])
        }

        final class Snapshot: @unchecked Sendable {
            let lock = NSLock()
            var tags: [String] = []

            func update(_ tags: [String]) {
                lock.lock()
                self.tags = tags
                lock.unlock()
            }

            func read() -> [String] {
                lock.lock()
                defer { lock.unlock() }
                return tags
            }
        }

        final class Handler: NSObject, OMLibboxCommandClientHandlerProtocol {
            private let snapshot: Snapshot
            private let onUpdate: () -> Void

            init(snapshot: Snapshot, onUpdate: @escaping () -> Void) {
                self.snapshot = snapshot
                self.onUpdate = onUpdate
            }

            func connected() {}
            func disconnected(_ message: String?) { _ = message }
            func clearLogs() {}
            func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) { _ = messageList }
            func writeStatus(_ message: OMLibboxStatusMessage?) { _ = message }

            func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {
                guard let groups else { return }
                var tags: [String] = []

                func stable(_ s: String) -> String {
                    String(decoding: Array(s.utf8), as: UTF8.self)
                }

                while groups.hasNext() {
                    guard let g = groups.next() else { break }
                    tags.append(stable(g.tag))
                }

                snapshot.update(tags)
                onUpdate()
            }

            func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) { _ = modeList; _ = currentMode }
            func updateClashMode(_ newMode: String?) { _ = newMode }
            func write(_ message: OMLibboxConnections?) { _ = message }
        }

        let snapshot = Snapshot()
        let updateSema = DispatchSemaphore(value: 0)
        let handler = Handler(snapshot: snapshot) { updateSema.signal() }

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandGroup
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(handler, options) else {
            throw NSError(domain: "com.meshflux", code: 5197, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandClient returned nil"])
        }
        defer { _ = try? client.disconnect() }

        var connected = false
        for i in 0 ..< 20 {
            do {
                try client.connect()
                connected = true
                break
            } catch {
                Thread.sleep(forTimeInterval: 0.05 + Double(i) * 0.03)
            }
        }
        guard connected else {
            throw NSError(domain: "com.meshflux", code: 5196, userInfo: [NSLocalizedDescriptionKey: "command client connect failed"])
        }

        _ = updateSema.wait(timeout: .now() + timeoutSeconds)
        return snapshot.read()
    }

    private func urlTestAndSnapshotDelays(groupTag: String, timeoutSeconds: TimeInterval) throws -> [String: Int] {
        guard boxService != nil else {
            throw NSError(domain: "com.meshflux", code: 5201, userInfo: [NSLocalizedDescriptionKey: "service not running"])
        }

        final class Snapshot: @unchecked Sendable {
            let lock = NSLock()
            var maxItemTime: Double = 0
            var delays: [String: Int] = [:]
            var itemTimes: [String: Double] = [:]
            var groupFound = false

            func update(maxItemTime: Double, delays: [String: Int], itemTimes: [String: Double], groupFound: Bool) {
                lock.lock()
                self.maxItemTime = maxItemTime
                self.delays = delays
                self.itemTimes = itemTimes
                self.groupFound = groupFound
                lock.unlock()
            }

            func read() -> (maxItemTime: Double, delays: [String: Int], itemTimes: [String: Double], groupFound: Bool) {
                lock.lock()
                defer { lock.unlock() }
                return (maxItemTime, delays, itemTimes, groupFound)
            }
        }

        final class Handler: NSObject, OMLibboxCommandClientHandlerProtocol {
            private let groupTagLower: String
            private let snapshot: Snapshot
            private let onUpdate: () -> Void

            init(groupTag: String, snapshot: Snapshot, onUpdate: @escaping () -> Void) {
                self.groupTagLower = groupTag.lowercased()
                self.snapshot = snapshot
                self.onUpdate = onUpdate
            }

            func connected() {}
            func disconnected(_ message: String?) { _ = message }
            func clearLogs() {}
            func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) { _ = messageList }
            func writeStatus(_ message: OMLibboxStatusMessage?) { _ = message }

            func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {
                guard let groups else { return }
                var delays: [String: Int] = [:]
                var itemTimes: [String: Double] = [:]
                var maxTime: Double = 0
                var found = false

                func stable(_ s: String) -> String {
                    String(decoding: Array(s.utf8), as: UTF8.self)
                }

                while groups.hasNext() {
                    guard let g = groups.next() else { break }
                    let tag = stable(g.tag)
                    if tag.lowercased() != groupTagLower { continue }
                    found = true
                    if let items = g.getItems() {
                        while items.hasNext() {
                            guard let it = items.next() else { break }
                            let itemTag = stable(it.tag)
                            let t = Double(it.urlTestTime)
                            if t > maxTime { maxTime = t }
                            itemTimes[itemTag] = t
                            let d = Int(it.urlTestDelay)
                            delays[itemTag] = d
                        }
                    }
                    break
                }

                snapshot.update(maxItemTime: maxTime, delays: delays, itemTimes: itemTimes, groupFound: found)
                onUpdate()
            }

            func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) { _ = modeList; _ = currentMode }
            func updateClashMode(_ newMode: String?) { _ = newMode }
            func write(_ message: OMLibboxConnections?) { _ = message }
        }

        let snapshot = Snapshot()
        let updateSema = DispatchSemaphore(value: 0)
        let handler = Handler(groupTag: groupTag, snapshot: snapshot) { updateSema.signal() }

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandGroup
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(handler, options) else {
            throw NSError(domain: "com.meshflux", code: 5202, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandClient returned nil"])
        }
        defer { _ = try? client.disconnect() }

        var connected = false
        for i in 0 ..< 20 {
            do {
                try client.connect()
                connected = true
                break
            } catch {
                Thread.sleep(forTimeInterval: 0.05 + Double(i) * 0.03)
            }
        }
        guard connected else {
            throw NSError(domain: "com.meshflux", code: 5203, userInfo: [NSLocalizedDescriptionKey: "command client connect failed"])
        }

        _ = updateSema.wait(timeout: .now() + 2.0)
        let (_, baselineDelays, baselineItemTimes, baselineGroupFound) = snapshot.read()

        var candidateTags = Set(baselineDelays.keys).union(baselineItemTimes.keys)
        if let line = "[urltest-debug] phase=baseline group=\(groupTag) group_found=\(baselineGroupFound ? 1 : 0) tags=\(Array(candidateTags).sorted().joined(separator: ",")) delays=\(baselineDelays)\n".data(using: .utf8) {
            FileHandle.standardError.write(line)
        }

        try client.urlTest(groupTag)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var latestDelays = baselineDelays
        var latestItemTimes = baselineItemTimes
        var latestGroupFound = baselineGroupFound

        func allCandidatesAdvanced(_ itemTimes: [String: Double], tags: Set<String>) -> Bool {
            guard !tags.isEmpty else { return false }
            for tag in tags {
                if (itemTimes[tag] ?? 0) <= (baselineItemTimes[tag] ?? 0) { return false }
            }
            return true
        }

        while Date() < deadline {
            _ = updateSema.wait(timeout: .now() + 0.6)
            let (_, d, itemTimes, found) = snapshot.read()
            latestDelays = d
            latestItemTimes = itemTimes
            latestGroupFound = found

            if candidateTags.isEmpty {
                candidateTags = Set(d.keys).union(itemTimes.keys)
            }

            if allCandidatesAdvanced(itemTimes, tags: candidateTags) {
                if let line = "[urltest-debug] phase=complete group=\(groupTag) tags=\(Array(candidateTags).sorted().joined(separator: ",")) delays=\(d)\n".data(using: .utf8) {
                    FileHandle.standardError.write(line)
                }
                return d
            }
        }

        if let line = "[urltest-debug] phase=timeout group=\(groupTag) group_found=\(latestGroupFound ? 1 : 0) tags=\(Array(candidateTags).sorted().joined(separator: ",")) delays=\(latestDelays) item_times=\(latestItemTimes)\n".data(using: .utf8) {
            FileHandle.standardError.write(line)
        }

        if !latestDelays.isEmpty {
            return latestDelays
        }

        throw NSError(domain: "com.meshflux", code: 5204, userInfo: [NSLocalizedDescriptionKey: "urltest timeout"])
    }

    private func handleAppMessage0(_ messageData: Data) -> Data? {
        // Expected JSON:
        // {"action":"reload"}
        // {"action":"update_rules","format":"json"|"txt","content":"..."}
        // {"action":"urltest","group":"proxy"} // group optional
        // {"action":"select_outbound","group":"proxy","outbound":"meshflux252"}
        do {
            let obj = try JSONSerialization.jsonObject(with: messageData, options: [.fragmentsAllowed])
            guard let dict = obj as? [String: Any], let action = dict["action"] as? String else {
                return messageData
            }

            switch action {
            case "reload":
                scheduleReload(reason: "app")
                return #"{"ok":true}"#.data(using: .utf8)
            case "urltest":
                do {
                    let requested = dict["group"] as? String
                    let groupTag = (requested?.isEmpty == false) ? requested! : nil
                    let resolvedGroupTag: String
                    if let groupTag {
                        resolvedGroupTag = groupTag
                    } else {
                        resolvedGroupTag = try pickPreferredURLTestGroupTag(timeoutSeconds: 2.0)
                    }
                    let delays = try urlTestAndSnapshotDelays(groupTag: resolvedGroupTag, timeoutSeconds: 12)
                    let payload: [String: Any] = ["ok": true, "group": resolvedGroupTag, "delays": delays]
                    return try JSONSerialization.data(withJSONObject: payload, options: [])
                } catch {
                    let payload: [String: Any] = ["ok": false, "error": String(describing: error)]
                    return try? JSONSerialization.data(withJSONObject: payload, options: [])
                }
            case "select_outbound":
                do {
                    guard let group0 = dict["group"] as? String, !group0.isEmpty else {
                        throw NSError(domain: "com.meshflux", code: 5301, userInfo: [NSLocalizedDescriptionKey: "missing group tag"])
                    }
                    guard let outbound0 = dict["outbound"] as? String, !outbound0.isEmpty else {
                        throw NSError(domain: "com.meshflux", code: 5302, userInfo: [NSLocalizedDescriptionKey: "missing outbound tag"])
                    }

                    let group = String(decoding: Array(group0.utf8), as: UTF8.self)
                    let outbound = String(decoding: Array(outbound0.utf8), as: UTF8.self)

                    func validate(_ s: String) -> Bool {
                        if s.isEmpty { return false }
                        if s.count > 256 { return false }
                        for u in s.unicodeScalars {
                            let v = u.value
                            if v < 0x20 || v == 0x7F { return false }
                        }
                        return true
                    }
                    guard validate(group), validate(outbound) else {
                        throw NSError(domain: "com.meshflux", code: 5303, userInfo: [NSLocalizedDescriptionKey: "invalid tag"])
                    }
                    guard boxService != nil else {
                        throw NSError(domain: "com.meshflux", code: 5304, userInfo: [NSLocalizedDescriptionKey: "service not running"])
                    }

                    guard let client = OMLibboxNewStandaloneCommandClient() else {
                        throw NSError(domain: "com.meshflux", code: 5305, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient returned nil"])
                    }
                    try client.selectOutbound(group, outboundTag: outbound)
                    NSLog("MeshFlux VPN iOS extension select_outbound ok group=%@ outbound=%@", group, outbound)
                    let payload: [String: Any] = ["ok": true]
                    return try JSONSerialization.data(withJSONObject: payload, options: [])
                } catch {
                    NSLog("MeshFlux VPN iOS extension select_outbound failed: %@", String(describing: error))
                    let payload: [String: Any] = ["ok": false, "error": String(describing: error)]
                    return try? JSONSerialization.data(withJSONObject: payload, options: [])
                }
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
