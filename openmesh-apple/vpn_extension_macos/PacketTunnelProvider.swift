//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/18.
//

import NetworkExtension
import OpenMeshGo
import Foundation

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

    private func prepareBaseDirectories(fileManager: FileManager) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        // Align with sing-box: use App Group container as the shared root.
        let groupID = "group.com.meshnetprotocol.OpenMesh"
        guard let sharedDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container: \(groupID). Check Signing & Capabilities (App Groups) for both the app and the extension."])
        }

        let baseDirURL = sharedDir
        let cacheDirURL = sharedDir
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
        let workingDirURL = cacheDirURL.appendingPathComponent("Working", isDirectory: true)
        let sharedDataDirURL = sharedDir.appendingPathComponent("MeshFlux", isDirectory: true)

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

                // Revert to original order: create service, setService, start server, then start box service.
                // (Command server start() before setService may block or cause Plugin failed in our OpenMeshGo build.)
                let configContent = try self.buildConfigContent()
                var serviceErr: NSError?
                guard let boxService = OMLibboxNewService(configContent, platform, &serviceErr) else {
                    throw serviceErr ?? NSError(domain: "com.meshflux", code: 4, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewService failed"])
                }
                server.setService(boxService)
                self.boxService = boxService
                try server.start()
                NSLog("MeshFlux VPN extension command server started")
                try boxService.start()
                NSLog("MeshFlux VPN extension box service started")

                try self.startRulesWatcherIfNeeded()

                NSLog("MeshFlux VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("MeshFlux VPN extension startTunnel failed: %@", String(describing: error))
                completionHandler(error)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
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
            completionHandler()
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

    // MARK: - Dynamic Rules

    private func buildConfigContent() throws -> String {
        let template = try loadBaseConfigTemplateContent()
        let obj = try JSONSerialization.jsonObject(with: Data(template.utf8), options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else {
            throw NSError(domain: "com.meshflux", code: 3001, userInfo: [NSLocalizedDescriptionKey: "base config template is not a JSON object"])
        }
        guard var route = config["route"] as? [String: Any] else {
            throw NSError(domain: "com.meshflux", code: 3002, userInfo: [NSLocalizedDescriptionKey: "base config missing route section"])
        }

        var routeRules: [[String: Any]] = []
        if let existing = route["rules"] as? [Any] {
            for item in existing {
                if let dict = item as? [String: Any] {
                    routeRules.append(dict)
                }
            }
        }

        guard let sharedDataDirURL else {
            throw NSError(domain: "com.meshflux", code: 3004, userInfo: [NSLocalizedDescriptionKey: "Missing shared data directory (App Group MeshFlux)."])
        }

        // Routing mode: default is "rule" (match rules => proxy, otherwise direct).
        // If mode is "global", send all traffic to proxy by setting route.final = "proxy".
        let mode = readRoutingMode(from: sharedDataDirURL)
        let finalOutbound = (mode == "global") ? "proxy" : "direct"
        route["final"] = finalOutbound
        NSLog(
            "MeshFlux VPN extension routing mode=%@ (routing_mode.json=%@) route.final=%@",
            mode,
            sharedDataDirURL.appendingPathComponent("routing_mode.json", isDirectory: false).path,
            finalOutbound
        )

        let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
        if !FileManager.default.fileExists(atPath: jsonURL.path) {
            throw NSError(
                domain: "com.meshflux",
                code: 3005,
                userInfo: [NSLocalizedDescriptionKey: "Missing routing_rules.json in App Group: \(jsonURL.path). Launch the MeshFlux app once (or update rules) then reconnect VPN."]
            )
        }
        var rules = try DynamicRoutingRules.parseJSON(Data(contentsOf: jsonURL))
        rules.normalize()
        NSLog(
            "MeshFlux VPN extension dynamic rules loaded from %@ (ip=%d domain=%d suffix=%d regex=%d)",
            jsonURL.path,
            rules.ipCIDR.count,
            rules.domain.count,
            rules.domainSuffix.count,
            rules.domainRegex.count
        )
        let dynamicRules = rules.toSingBoxRouteRules(outboundTag: "proxy")
        NSLog("MeshFlux VPN extension: Generated %d dynamic route rules from loaded rules", dynamicRules.count)
        for (index, rule) in dynamicRules.enumerated() {
            if let domainSuffix = rule["domain_suffix"] as? [String] {
                let sampleSuffixes = domainSuffix.prefix(5).joined(separator: ", ")
                NSLog("MeshFlux VPN extension: Rule[%d] domain_suffix count=%d (sample: %@)", index, domainSuffix.count, sampleSuffixes)
            }
        }
        
        // CRITICAL: Rule order matters!
        // 1. sniff (extract domain from IP connections) - must be first
        // 2. domain_suffix rules (match extracted domain) - after sniff
        // 3. hijack-dns (DNS hijacking) - last
        
        // CRITICAL FIX: If base config doesn't have sniff rule, add it!
        var sniffIndex = -1
        for (index, rule) in routeRules.enumerated() {
            if let action = rule["action"] as? String, action == "sniff" {
                sniffIndex = index
                break
            }
        }
        
        if sniffIndex < 0 {
            // No sniff rule found - ADD IT!
            let sniffRule: [String: Any] = [
                "action": "sniff"
            ]
            routeRules.insert(sniffRule, at: 0)
            sniffIndex = 0
            NSLog("MeshFlux VPN extension: ADDED missing sniff rule at position 0")
        }
        
        // Insert domain rules right after sniff
        routeRules.insert(contentsOf: dynamicRules, at: sniffIndex + 1)
        NSLog("MeshFlux VPN extension: Inserted %d dynamic rules after sniff (at position %d). Total rules now: %d", dynamicRules.count, sniffIndex + 1, routeRules.count)

        route["rules"] = routeRules
        config["route"] = route

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let content = String(decoding: data, as: UTF8.self)
        
        // Log the final route rules for debugging
        if let routeDict = config["route"] as? [String: Any],
           let finalRules = routeDict["rules"] as? [[String: Any]] {
            NSLog("MeshFlux VPN extension: Final route rules count=%d", finalRules.count)
            for (index, rule) in finalRules.enumerated() {
                if let action = rule["action"] as? String {
                    NSLog("MeshFlux VPN extension: Route[%d] action=%@", index, action)
                } else if let domainSuffix = rule["domain_suffix"] as? [String] {
                    NSLog("MeshFlux VPN extension: Route[%d] domain_suffix count=%d outbound=%@", index, domainSuffix.count, rule["outbound"] as? String ?? "nil")
                } else if let outbound = rule["outbound"] as? String {
                    NSLog("MeshFlux VPN extension: Route[%d] outbound=%@ (other keys: %@)", index, outbound, Array(rule.keys).joined(separator: ", "))
                }
            }
        }
        
        try writeGeneratedConfigSnapshot(content)
        return content
    }

    private func readRoutingMode(from sharedDataDirURL: URL) -> String {
        let url = sharedDataDirURL.appendingPathComponent("routing_mode.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return "rule" }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return "rule" }
        guard let dict = obj as? [String: Any] else { return "rule" }
        guard let mode = dict["mode"] as? String else { return "rule" }
        return mode
    }

    private func loadBaseConfigTemplateContent() throws -> String {
        let fileManager = FileManager.default
        if let sharedDataDirURL {
            let overrideURL = sharedDataDirURL.appendingPathComponent("singbox_config.json", isDirectory: false)
            if fileManager.fileExists(atPath: overrideURL.path) {
                NSLog("MeshFlux VPN extension base config from App Group: %@", overrideURL.path)
                return String(decoding: try Data(contentsOf: overrideURL), as: UTF8.self)
            }
        }

        if let bundledURL = Bundle.main.url(forResource: "singbox_base_config", withExtension: "json") {
            NSLog("MeshFlux VPN extension base config from bundle: %@", bundledURL.path)
            return String(decoding: try Data(contentsOf: bundledURL), as: UTF8.self)
        }

        throw NSError(domain: "com.meshflux", code: 3003, userInfo: [NSLocalizedDescriptionKey: "Missing bundled singbox_base_config.json"])
    }

    private func writeGeneratedConfigSnapshot(_ content: String) throws {
        guard let cacheDirURL else { return }
        let url = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
        guard let data = content.data(using: .utf8) else { return }
        try data.write(to: url, options: [.atomic])
    }

    private func startRulesWatcherIfNeeded() throws {
        guard rulesWatcher == nil else { return }
        guard let sharedDataDirURL else { return }
        let watcher = FileSystemWatcher(url: sharedDataDirURL, queue: serviceQueue) { [weak self] in
            self?.scheduleReload(reason: "fs")
        }
        try watcher.start()
        rulesWatcher = watcher
        NSLog("MeshFlux VPN extension rules watcher started: %@", sharedDataDirURL.path)
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
            let content = try buildConfigContent()
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
                guard let sharedDataDirURL else {
                    return #"{"ok":false,"error":"missing sharedDataDirURL"}"#.data(using: .utf8)
                }
                guard let format = dict["format"] as? String, let content = dict["content"] as? String else {
                    return #"{"ok":false,"error":"missing format/content"}"#.data(using: .utf8)
                }
                let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
                switch format.lowercased() {
                case "json":
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
