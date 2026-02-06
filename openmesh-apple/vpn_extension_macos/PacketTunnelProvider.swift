//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/18.
//

import NetworkExtension
import OpenMeshGo
import Foundation
import VPNLibrary

// Match sing-box structure: PacketTunnelProvider is a thin subclass; logic lives in ExtensionProvider.
class ExtensionProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var boxService: OMLibboxBoxService?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?
    private var cacheDirURL: URL?

    private let serviceQueue = DispatchQueue(label: "com.meshflux.vpn.service", qos: .userInitiated)
    private var pendingReload: DispatchWorkItem?
    /// 主程序心跳检测：若连续 3 次（约 30s）未读到更新，认为主程序已退出，主动关闭 VPN。
    private var heartbeatCheckWorkItem: DispatchWorkItem?
    private var heartbeatMissCount: Int = 0
    private static let heartbeatCheckInterval: TimeInterval = 10
    private static let heartbeatMaxAge: TimeInterval = 30
    private static let heartbeatMissesBeforeStop = 3

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
        self.cacheDirURL = cacheDirURL
        // Use relativePath to align with sing-box ExtensionProvider (SFM); on macOS App Group URL both are typically the same.
        return (
            baseDirURL: baseDirURL,
            basePath: baseDirURL.relativePath,
            workingPath: workingDirURL.relativePath,
            tempPath: cacheDirURL.relativePath
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

                // Align with sing-box ExtensionProvider: server.start() first, then NewService → service.start() → setService(service).
                try server.start()
                NSLog("MeshFlux VPN extension command server started")
                let configContent = try self.resolveConfigContent()
                NSLog("MeshFlux VPN extension: passing config to libbox. stderr.log: %@", stderrLogPath)
                var serviceErr: NSError?
                guard let boxService = OMLibboxNewService(configContent, platform, &serviceErr) else {
                    throw serviceErr ?? NSError(domain: "com.meshflux", code: 4, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewService failed"])
                }
                try boxService.start()
                NSLog("MeshFlux VPN extension box service started")
                server.setService(boxService)
                self.boxService = boxService

                self.startHeartbeatCheck()
                NSLog("MeshFlux VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("MeshFlux VPN extension startTunnel failed: %@", String(describing: error))
                completionHandler(error)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Explicitly clear tunnel network settings first so the system releases our routes/primary
        // immediately. Otherwise the session can leave stale state and cause "not primary for IPv4/IPv6"
        // when starting another VPN (e.g. system-level MeshFlux X) later.
        setTunnelNetworkSettings(nil) { [weak self] _ in
            self?.serviceQueue.async {
                guard let self = self else { completionHandler(); return }
                self.pendingReload?.cancel()
                self.pendingReload = nil
                self.heartbeatCheckWorkItem?.cancel()
                self.heartbeatCheckWorkItem = nil

                try? self.boxService?.close()
                try? self.commandServer?.close()
                self.boxService = nil
                self.commandServer = nil
                self.platformInterface?.reset()
                self.platformInterface = nil
                if let baseDirURL = self.baseDirURL {
                    self.cleanupStaleCommandSocket(in: baseDirURL, fileManager: .default)
                }
                completionHandler()
            }
        }
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        serviceQueue.async {
            let response = self.handleAppMessage0(messageData)
            completionHandler?(response)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Align with sing-box: pause box service when system sleeps.
        boxService?.pause()
        completionHandler()
    }

    override func wake() {
        // Align with sing-box: resume box service when system wakes.
        boxService?.wake()
    }

    // MARK: - Config resolution (profile-driven only)

    /// Applies the main app's preferred outbound selection (per-profile) by patching selector/urltest
    /// outbounds' `default` field. This makes "switch node" durable across reloads/reconnects without
    /// calling `selectOutbound` from the main app process.
    private func applyPreferredOutboundSelectionToConfigContent(_ content: String) -> String {
        let profileID = SharedPreferences.selectedProfileID.getBlocking()
        guard profileID >= 0 else { return content }

        let map = SharedPreferences.selectedOutboundTagByProfile.getBlocking()
        guard let desired = map["\(profileID)"], !desired.isEmpty else { return content }

        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              var config = obj as? [String: Any],
              var outbounds = config["outbounds"] as? [[String: Any]] else {
            return content
        }

        // Important: sing-box Selector prefers cache_file stored selection over config.default.
        // When urltest/selector selection has been stored previously, a reload would otherwise
        // "snap back" to the cached selection and ignore our patched default. To make the
        // app-side preference authoritative, use a cache_id derived from the preferred outbound.
        //
        // This isolates cache buckets per (profileID, desired) so LoadSelected(...) returns empty
        // unless it was stored under the same preferred value.
        func sanitizeCacheIDComponent(_ s: String) -> String {
            // Keep it ASCII and stable (bbolt bucket name). Avoid huge strings.
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
            let trimmed = s.prefix(64)
            let mapped = trimmed.map { allowed.contains($0) ? $0 : "_" }
            return String(mapped)
        }

        let cacheID = "meshflux_profile_\(profileID)_" + sanitizeCacheIDComponent(desired)
        var experimental = (config["experimental"] as? [String: Any]) ?? [:]
        var cacheFile = (experimental["cache_file"] as? [String: Any]) ?? [:]
        cacheFile["cache_id"] = cacheID
        experimental["cache_file"] = cacheFile
        config["experimental"] = experimental

        func candidatesContainDesired(_ outbound: [String: Any]) -> Bool {
            if let list = outbound["outbounds"] as? [String] { return list.contains(desired) }
            if let list = outbound["outbounds"] as? [Any] { return list.compactMap { $0 as? String }.contains(desired) }
            return false
        }

        func isSelectorLike(_ type: String) -> Bool {
            let t = type.lowercased()
            return t == "selector" || t == "urltest"
        }

        // Patch all relevant selector/urltest groups that contain the desired outbound.
        // Do NOT stop after the first match: some configs route via "auto" (urltest) while others use "proxy" (selector).
        let preferredGroupTags = Set(["proxy", "auto"])
        var patchedTags: [String] = []
        var didPatchPreferred = false

        for (i, ob) in outbounds.enumerated() {
            guard let type = ob["type"] as? String, isSelectorLike(type) else { continue }
            let tag = ((ob["tag"] as? String) ?? "")
            if !preferredGroupTags.contains(tag.lowercased()) { continue }
            if candidatesContainDesired(ob) {
                outbounds[i]["default"] = desired
                patchedTags.append(tag)
                didPatchPreferred = true
            }
        }

        if !didPatchPreferred {
            for (i, ob) in outbounds.enumerated() {
                guard let type = ob["type"] as? String, isSelectorLike(type) else { continue }
                let tag = ((ob["tag"] as? String) ?? "")
                if candidatesContainDesired(ob) {
                    outbounds[i]["default"] = desired
                    patchedTags.append(tag)
                }
            }
        }

        guard !patchedTags.isEmpty else { return content }

        config["outbounds"] = outbounds
        guard let patched = try? JSONSerialization.data(withJSONObject: config, options: []) else { return content }
        let str = String(data: patched, encoding: .utf8) ?? content
        NSLog(
            "MeshFlux VPN extension: applied preferred outbound profile=%lld default=%@ groups=%@ cache_id=%@",
            profileID, desired, String(describing: patchedTags), cacheID
        )
        if let line = "MeshFlux VPN extension: applyPreferredOutbound profile=\(profileID) default=\(desired) groups=\(patchedTags) cache_id=\(cacheID)\n".data(using: .utf8) {
            // Stderr is redirected to App Group cache stderr.log during startup.
            FileHandle.standardError.write(line)
        }
        return str
    }

    /// Resolves config: selectedProfileID → Profile → profile.read(); else bundled default_profile.json; else 报错（不再使用旧回退路径）。
    /// Raw profile mode: do not rewrite route/dns by app mode.
    private func resolveConfigContent() throws -> String {
        let profileID = SharedPreferences.selectedProfileID.getBlocking()
        var content: String
        if profileID >= 0, let profile = try? ProfileManager.getBlocking(profileID) {
            do {
                content = try profile.read()
                NSLog("MeshFlux VPN extension using profile-driven config (id=%lld, name=%@)", profileID, profile.name)
            } catch {
                NSLog("MeshFlux VPN extension profile.read() failed: %@, trying default_profile", String(describing: error))
                content = try loadDefaultProfileContent()
            }
        } else {
            content = try loadDefaultProfileContent()
        }

        // 1) Patch selector default based on app-side preference (switch node).
        // 2) Inject bundled/app-group routing_rules.json so it can override built-in geosite direct rules
        //    (e.g. geosite-geolocation-cn can include some Google API domains; without injection, they
        //    get routed to direct and time out behind restricted networks).
        // 3) Apply routing mode patch (global/split mode). (Raw-profile mode: no route/dns mutations.)
        let withPreferred = applyPreferredOutboundSelectionToConfigContent(content)
        let withRules = applyDynamicRoutingRulesToConfigContent(withPreferred)
        return applyRoutingModeToConfigContent(withRules, isGlobalMode: false)
    }

    // MARK: - Dynamic routing rules injection (routing_rules.json)

    /// Injects routing_rules.json (App Group preferred; falls back to bundled resource) into route.rules,
    /// immediately after sniff, so these rules take precedence over geosite-geolocation-cn direct routing.
    private func applyDynamicRoutingRulesToConfigContent(_ content: String) -> String {
        guard let baseDirURL else { return content }
        let sharedDataDirURL = baseDirURL.appendingPathComponent("MeshFlux", isDirectory: true)

        do {
            let loaded = try DynamicRoutingRules.loadPreferNewest(from: sharedDataDirURL, fallbackBundle: Bundle.main)
            var rules = loaded.rules
            rules.normalize()
            if rules.isEmpty {
                // Hard fallback: make Google OAuth usable even when routing_rules.json is missing.
                // Some geosite-geolocation-cn lists include googleapis/gstatic which would otherwise
                // be routed to `direct` and time out behind restricted networks.
                rules.domainSuffix = [
                    "google.com",
                    "googleapis.com",
                    "gstatic.com",
                    "googleusercontent.com",
                    "ggpht.com",
                ]
                rules.normalize()
                if let line = "MeshFlux VPN extension: routing_rules empty/missing; using built-in google fallback rules\n".data(using: .utf8) {
                    FileHandle.standardError.write(line)
                }
            }

            guard var obj = parseConfigObjectRelaxed(content) else {
                if let line = "MeshFlux VPN extension: inject routing_rules skipped (config parse failed)\n".data(using: .utf8) {
                    FileHandle.standardError.write(line)
                }
                return content
            }
            var route = (obj["route"] as? [String: Any]) ?? [:]
            var routeRules: [[String: Any]] = []
            if let existing = route["rules"] as? [Any] {
                routeRules = existing.compactMap { $0 as? [String: Any] }
            }

            // Remove previous injections to avoid duplicates on reload.
            //
            // IMPORTANT: Do NOT add custom fields into sing-box config (it fails strict decoding).
            // Instead, de-dup by exact rule content (canonical JSON) before insertion.
            func canonicalRule(_ rule: [String: Any]) -> String {
                var r = rule
                // Normalize list fields so equivalent rules compare equal even if ordering differs.
                for key in ["ip_cidr", "domain", "domain_suffix", "domain_regex"] {
                    if let arr = r[key] as? [String] {
                        r[key] = arr.sorted()
                    } else if let arr = r[key] as? [Any] {
                        r[key] = arr.compactMap { $0 as? String }.sorted()
                    }
                }
                let data = (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])) ?? Data()
                return String(decoding: data, as: UTF8.self)
            }

            // Ensure sniff exists and find insertion index (right after sniff).
            var sniffIndex: Int? = nil
            for (i, r) in routeRules.enumerated() {
                if (r["action"] as? String) == "sniff" {
                    sniffIndex = i
                    break
                }
            }
            if sniffIndex == nil {
                routeRules.insert(["action": "sniff"], at: 0)
                sniffIndex = 0
            }

            let injected = rules.toSingBoxRouteRules(outboundTag: "proxy")
            let injectedCanonicals = Set(injected.map(canonicalRule))
            routeRules.removeAll { injectedCanonicals.contains(canonicalRule($0)) }

            routeRules.insert(contentsOf: injected, at: (sniffIndex ?? 0) + 1)
            route["rules"] = routeRules
            obj["route"] = route

            let out = try JSONSerialization.data(withJSONObject: obj, options: [])
            let str = String(decoding: out, as: UTF8.self)
            let source = loaded.sourceURL?.path ?? "(built-in fallback)"
            NSLog("MeshFlux VPN extension: injected routing_rules (%d rules) from %@", injected.count, source)
            if let line = "MeshFlux VPN extension: injected routing_rules count=\(injected.count) source=\(source)\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
            return str
        } catch {
            NSLog("MeshFlux VPN extension: inject routing_rules failed: %@", String(describing: error))
            if let line = "MeshFlux VPN extension: inject routing_rules failed: \(String(describing: error))\n".data(using: .utf8) {
                FileHandle.standardError.write(line)
            }
            return content
        }
    }

    /// sing-box configs can be JSONC/JSON5-ish (comments, trailing commas). Foundation JSONSerialization is strict.
    /// This pre-processor strips comments and trailing commas *outside of strings* to make parsing robust.
    private func parseConfigObjectRelaxed(_ content: String) -> [String: Any]? {
        guard let cleaned = stripJSONCommentsAndTrailingCommas(content) else { return nil }
        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return obj as? [String: Any]
    }

    private func stripJSONCommentsAndTrailingCommas(_ s: String) -> String? {
        let chars = Array(s.unicodeScalars)
        var out: [UnicodeScalar] = []
        out.reserveCapacity(chars.count)

        var i = 0
        var inString = false
        var escape = false

        func peek(_ offset: Int) -> UnicodeScalar? {
            let j = i + offset
            if j < 0 || j >= chars.count { return nil }
            return chars[j]
        }

        // 1) Strip comments outside strings.
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            if c == "\"" {
                inString = true
                out.append(c)
                i += 1
                continue
            }

            if c == "/", let n = peek(1) {
                if n == "/" {
                    i += 2
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                    continue
                }
                if n == "*" {
                    i += 2
                    while i + 1 < chars.count {
                        if chars[i] == "*" && chars[i + 1] == "/" {
                            i += 2
                            break
                        }
                        i += 1
                    }
                    continue
                }
            }

            out.append(c)
            i += 1
        }

        let stripped = String(String.UnicodeScalarView(out))
        let chars2 = Array(stripped.unicodeScalars)
        var out2: [UnicodeScalar] = []
        out2.reserveCapacity(chars2.count)

        i = 0
        inString = false
        escape = false

        func nextNonWS(from idx: Int) -> UnicodeScalar? {
            var j = idx
            while j < chars2.count {
                let u = chars2[j]
                if u != " " && u != "\t" && u != "\n" && u != "\r" { return u }
                j += 1
            }
            return nil
        }

        while i < chars2.count {
            let c = chars2[i]
            if inString {
                out2.append(c)
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out2.append(c)
                i += 1
                continue
            }
            if c == "," {
                if let n = nextNonWS(from: i + 1), (n == "]" || n == "}") {
                    i += 1
                    continue
                }
            }
            out2.append(c)
            i += 1
        }

        return String(String.UnicodeScalarView(out2))
    }

    private func loadDefaultProfileContent() throws -> String {
        let defaultProfileURL = Bundle.main.url(forResource: "default_profile", withExtension: "json")
            ?? Bundle.main.url(forResource: "default_profile", withExtension: "json", subdirectory: "MeshFluxMac")
        if let url = defaultProfileURL,
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8), !content.isEmpty {
            NSLog("MeshFlux VPN extension using bundled default_profile.json")
            return content
        }
        throw NSError(domain: "com.meshflux", code: 3010, userInfo: [NSLocalizedDescriptionKey: "No profile selected and no default profile. Please create or select a profile in the app, then reconnect VPN."])
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
            NSLog("MeshFlux VPN extension reloadService(%@) begin", reason)
            // Align with sing-box / macx: close old service and setService(nil) first, then create+start new service.
            try? boxService?.close()
            commandServer.setService(nil)
            boxService = nil
            let content = try resolveConfigContent()
            var serviceErr: NSError?
            guard let newService = OMLibboxNewService(content, platform, &serviceErr) else {
                NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: serviceErr))
                return
            }
            try newService.start()
            commandServer.setService(newService)
            boxService = newService
            NSLog("MeshFlux VPN extension reloadService(%@) done", reason)
        } catch {
            NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: error))
        }
    }

    private func startHeartbeatCheck() {
        heartbeatCheckWorkItem?.cancel()
        heartbeatMissCount = 0
        scheduleHeartbeatCheck()
    }

    private func scheduleHeartbeatCheck() {
        let work = DispatchWorkItem { [weak self] in
            self?.performHeartbeatCheck()
        }
        heartbeatCheckWorkItem = work
        serviceQueue.asyncAfter(deadline: .now() + Self.heartbeatCheckInterval, execute: work)
    }

    private func performHeartbeatCheck() {
        heartbeatCheckWorkItem = nil
        let url = FilePath.appHeartbeatFile
        let now = Date().timeIntervalSince1970
        var missed = true
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let ts = Double(line), (now - ts) <= Self.heartbeatMaxAge {
            missed = false
        }
        if missed {
            heartbeatMissCount += 1
            if heartbeatMissCount >= Self.heartbeatMissesBeforeStop {
                NSLog("MeshFlux VPN extension: main app heartbeat missed %d times, stopping tunnel", heartbeatMissCount)
                cancelTunnelWithError(nil)
                return
            }
        } else {
            heartbeatMissCount = 0
        }
        scheduleHeartbeatCheck()
    }

    private func pickPreferredURLTestGroupTag(timeoutSeconds: TimeInterval) throws -> String {
        let tags = try snapshotOutboundGroupTags(timeoutSeconds: timeoutSeconds)
        guard !tags.isEmpty else {
            throw NSError(domain: "com.meshflux", code: 5199, userInfo: [NSLocalizedDescriptionKey: "no outbound groups available"])
        }

        // Align with UI expectations: prefer "proxy" selector, then "auto".
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
        // urltest relies on the running libbox instance; require an active service.
        guard boxService != nil else {
            throw NSError(domain: "com.meshflux", code: 5201, userInfo: [NSLocalizedDescriptionKey: "service not running"])
        }

        final class Snapshot: @unchecked Sendable {
            let lock = NSLock()
            var maxItemTime: Double = 0
            var delays: [String: Int] = [:]

            func update(maxItemTime: Double, delays: [String: Int]) {
                lock.lock()
                self.maxItemTime = maxItemTime
                self.delays = delays
                lock.unlock()
            }

            func read() -> (maxItemTime: Double, delays: [String: Int]) {
                lock.lock()
                defer { lock.unlock() }
                return (maxItemTime, delays)
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
                var maxTime: Double = 0

                func stable(_ s: String) -> String {
                    String(decoding: Array(s.utf8), as: UTF8.self)
                }

                while groups.hasNext() {
                    guard let g = groups.next() else { break }
                    let tag = stable(g.tag)
                    if tag.lowercased() != groupTagLower { continue }
                    if let items = g.getItems() {
                        while items.hasNext() {
                            guard let it = items.next() else { break }
                            let itemTag = stable(it.tag)
                            let t = Double(it.urlTestTime)
                            if t > maxTime { maxTime = t }
                            let d = Int(it.urlTestDelay)
                            delays[itemTag] = d
                        }
                    }
                    break
                }

                snapshot.update(maxItemTime: maxTime, delays: delays)
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
        let (baselineTime, baselineDelays) = snapshot.read()

        try client.urlTest(groupTag)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            _ = updateSema.wait(timeout: .now() + 0.6)
            let (t, d) = snapshot.read()
            if t > baselineTime { return d }
            if d != baselineDelays, d.values.contains(where: { $0 > 0 }) { return d }
        }

        throw NSError(domain: "com.meshflux", code: 5204, userInfo: [NSLocalizedDescriptionKey: "urltest timeout"])
    }

    private func handleAppMessage0(_ messageData: Data) -> Data? {
        // Expected JSON:
        // {"action":"reload"}
        // {"action":"update_rules","format":"json"|"txt","content":"..."}
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

                    // Defensive: deep-copy tags immediately (avoid any transient buffer surprises).
                    let group = String(decoding: Array(group0.utf8), as: UTF8.self)
                    let outbound = String(decoding: Array(outbound0.utf8), as: UTF8.self)

                    // Basic tag validation: keep it ASCII-ish and free of control characters.
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
                    NSLog("MeshFlux VPN extension select_outbound ok group=%@ outbound=%@", group, outbound)
                    let payload: [String: Any] = ["ok": true]
                    return try JSONSerialization.data(withJSONObject: payload, options: [])
                } catch {
                    NSLog("MeshFlux VPN extension select_outbound failed: %@", String(describing: error))
                    let payload: [String: Any] = ["ok": false, "error": String(describing: error)]
                    return try? JSONSerialization.data(withJSONObject: payload, options: [])
                }
            default:
                return messageData
            }
        } catch {
            return messageData
        }
    }
}

final class PacketTunnelProvider: ExtensionProvider {}
