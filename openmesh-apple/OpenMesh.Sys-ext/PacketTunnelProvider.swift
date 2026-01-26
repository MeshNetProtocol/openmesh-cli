//
//  PacketTunnelProvider.swift
//  OpenMesh.Sys-ext
//
//  Created by wesley on 2026/1/23.
//

import NetworkExtension
import OpenMeshGo
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?
    private var sharedDataDirURL: URL?
    private var cacheDirURL: URL?
    private var configContentOverride: String?
    private var rulesContentOverride: String?
    private var username: String?

    private let serviceQueue = DispatchQueue(label: "com.openmesh.vpn.service.system", qos: .userInitiated)
    private var rulesWatcher: FileSystemWatcher?
    private var pendingReload: DispatchWorkItem?

    // System Extensions run as root, so we must manually construct the path to the user's Group Container.
    // We cannot use FileManager.default.containerURL(...) because it would return the root user's container.
    private func prepareBaseDirectories(fileManager: FileManager, username: String) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        let groupID = "group.com.meshnetprotocol.OpenMesh.macsys"
        
        // Config: Read from User's Group Container
        let userGroupContainerURL = URL(fileURLWithPath: "/Users/\(username)/Library/Group Containers/\(groupID)")
        self.sharedDataDirURL = userGroupContainerURL.appendingPathComponent("OpenMesh", isDirectory: true)

        // Runtime: Use System/Extension Temp Directory (avoid permission issues)
        // System Extension (root) creates these in /private/tmp or /var/folders/...
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        let baseDirURL = tempRoot.appendingPathComponent("OpenMesh_Sys_Runtime", isDirectory: true)
        
        // Replicate the expected structure: base -> Library -> Caches
        let libCacheDir = baseDirURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            
        let workingDirURL = libCacheDir.appendingPathComponent("Working", isDirectory: true)
        let cacheDirURL = libCacheDir // This matches FilePath.cacheDirectory logic
        
        self.cacheDirURL = cacheDirURL

        // Create Runtime Directories (System Extension owns these)
        try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: libCacheDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)

        // Cleanup stale socket in temp dir
        cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)
        
        let commandSocketPath = baseDirURL.appendingPathComponent("command.sock", isDirectory: false).path
        NSLog("OpenMesh System VPN: ConfigDir=%@ BaseDir(Socket)=%@ WorkingDir=%@", 
              self.sharedDataDirURL?.path ?? "nil", baseDirURL.path, workingDirURL.path)

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

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("OpenMesh System VPN extension startTunnel begin")
        NSLog("OpenMesh System VPN extension options: %@", String(describing: options))
        
        // Capture injected config content
        if let configStr = options?["singbox_config_content"] as? String {
            self.configContentOverride = configStr
            NSLog("OpenMesh System VPN: Captured injected config content (len=%d)", configStr.count)
        }
        if let rulesStr = options?["routing_rules_content"] as? String {
            self.rulesContentOverride = rulesStr
            NSLog("OpenMesh System VPN: Captured injected rules content (len=%d)", rulesStr.count)
        }
        
        // CRITICAL: Retrieve username passed from the App
        // Fallback mechanism: try options first, then environment, then ProcessInfo
        var username: String?
        
        if let optUsername = options?["username"] as? String, !optUsername.isEmpty {
            username = optUsername
            NSLog("OpenMesh System VPN: Got username from options: %@", optUsername)
        } else {
            // Fallback 1: Try to get from environment
            if let envUser = ProcessInfo.processInfo.environment["USER"], !envUser.isEmpty {
                username = envUser
                NSLog("OpenMesh System VPN: Got username from environment: %@", envUser)
            } else {
                // Fallback 2: Try NSUserName (may not work for root)
                let nsUser = NSUserName()
                if !nsUser.isEmpty && nsUser != "root" {
                    username = nsUser
                    NSLog("OpenMesh System VPN: Got username from NSUserName: %@", nsUser)
                }
            }
        }
        
        guard let finalUsername = username, !finalUsername.isEmpty else {
            let err = NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing username in start options. Options received: \(String(describing: options))"])
            NSLog("OpenMesh System VPN Error: %@", err.localizedDescription)
            completionHandler(err)
            return
        }
        self.username = finalUsername

        serviceQueue.async {
            var err: NSError?
            do {
                let fileManager = FileManager.default
                // Use the new prepare method with username
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager, username: finalUsername)
                let baseDirURL = prepared.baseDirURL
                let basePath = prepared.basePath
                let workingPath = prepared.workingPath
                let tempPath = prepared.tempPath

                self.baseDirURL = baseDirURL
                NSLog("OpenMesh System VPN extension baseDirURL=%@", baseDirURL.path)

                let setup = OMLibboxSetupOptions()
                setup.basePath = basePath
                setup.workingPath = workingPath
                setup.tempPath = tempPath
                setup.logMaxLines = 2000
                setup.debug = true
                guard OMLibboxSetup(setup, &err) else {
                    throw err ?? NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
                }

                let stderrLogPath = (baseDirURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Caches", isDirectory: true)
                    .appendingPathComponent("stderr.log", isDirectory: false)).path
                _ = OMLibboxRedirectStderr(stderrLogPath, &err)
                err = nil

                // Note: OpenMeshLibboxPlatformInterface needs to handle 'self' which is NEPacketTunnelProvider.
                // Ensure the sharing/interface is compatible.
                let platform = OpenMeshLibboxPlatformInterface(self)
                let server = OMLibboxNewCommandServer(platform, platform, &err)
                if let err { throw err }
                guard let server else {
                    throw NSError(domain: "com.openmesh", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
                }

                self.platformInterface = platform
                self.commandServer = server

                try server.start()
                NSLog("OpenMesh System VPN extension command server started")

                let configContent = try self.buildConfigContent()

                let override = OMLibboxOverrideOptions()
                override.autoRedirect = false

                NSLog("OpenMesh System VPN extension startOrReloadService begin")
                try server.startOrReloadService(configContent, options: override)
                NSLog("OpenMesh System VPN extension startOrReloadService done")

                try self.startRulesWatcherIfNeeded()

                NSLog("OpenMesh System VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("OpenMesh System VPN extension startTunnel failed: %@", String(describing: error))
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

            try? self.commandServer?.closeService()
            self.commandServer?.close()
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
        completionHandler()
    }

    override func wake() {}

    // MARK: - Dynamic Rules and Logic (Copied from App Extension)

    private func buildConfigContent() throws -> String {
        NSLog("OpenMesh System VPN: buildConfigContent started")
        NSLog("OpenMesh System VPN: sharedDataDirURL=%@", sharedDataDirURL?.path ?? "nil")
        NSLog("OpenMesh System VPN: cacheDirURL=%@", cacheDirURL?.path ?? "nil")
        
        let template = try loadBaseConfigTemplateContent()
        NSLog("OpenMesh System VPN: Loaded base config template, length=%d", template.count)
        
        let obj = try JSONSerialization.jsonObject(with: Data(template.utf8), options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else {
            throw NSError(domain: "com.openmesh", code: 3001, userInfo: [NSLocalizedDescriptionKey: "base config template is not a JSON object"])
        }
        guard var route = config["route"] as? [String: Any] else {
            throw NSError(domain: "com.openmesh", code: 3002, userInfo: [NSLocalizedDescriptionKey: "base config missing route section"])
        }

        var routeRules: [[String: Any]] = []
        if let existing = route["rules"] as? [Any] {
            for item in existing {
                if let dict = item as? [String: Any] {
                    routeRules.append(dict)
                }
            }
        }
        NSLog("OpenMesh System VPN: Existing route rules count=%d", routeRules.count)

        guard let sharedDataDirURL else {
            throw NSError(domain: "com.openmesh", code: 3004, userInfo: [NSLocalizedDescriptionKey: "Missing shared data directory."])
        }

        let mode = readRoutingMode(from: sharedDataDirURL)
        let finalOutbound = (mode == "global") ? "proxy" : "direct"
        route["final"] = finalOutbound
        
        NSLog("OpenMesh System VPN: mode=%@ final=%@", mode, finalOutbound)

        // Try memory-injected rules first
        if let rulesStr = self.rulesContentOverride {
            NSLog("OpenMesh System VPN: Using injected routing rules (len=%d)", rulesStr.count)
            do {
                guard let rulesData = rulesStr.data(using: .utf8) else { throw NSError(domain: "UTF8", code: 0) }
                var rules = try DynamicRoutingRules.parseJSON(rulesData)
                rules.normalize()
                let newRules = rules.toSingBoxRouteRules(outboundTag: "proxy")
                NSLog("OpenMesh System VPN: Parsed %d dynamic rules from injection", newRules.count)
                routeRules.append(contentsOf: newRules)
            } catch {
                NSLog("OpenMesh System VPN: Failed to parse injected routing rules: %@", error.localizedDescription)
            }
        } else {
            // Fallback to file reading
            let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                NSLog("OpenMesh System VPN: Found routing_rules.json at %@", jsonURL.path)
                do {
                    let rulesData = try Data(contentsOf: jsonURL)
                    NSLog("OpenMesh System VPN: routing_rules.json size=%d bytes", rulesData.count)
                    var rules = try DynamicRoutingRules.parseJSON(rulesData)
                    rules.normalize()
                    let newRules = rules.toSingBoxRouteRules(outboundTag: "proxy")
                    NSLog("OpenMesh System VPN: Parsed %d dynamic rules from file", newRules.count)
                    routeRules.append(contentsOf: newRules)
                } catch {
                    NSLog("OpenMesh System VPN: Failed to parse routing rules file: %@", error.localizedDescription)
                }
            } else {
                NSLog("OpenMesh System VPN: No routing_rules.json found (and no injection)")
            }
        }

        route["rules"] = routeRules
        config["route"] = route
        NSLog("OpenMesh System VPN: Final route rules count=%d", routeRules.count)

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let content = String(decoding: data, as: UTF8.self)
        try writeGeneratedConfigSnapshot(content)
        NSLog("OpenMesh System VPN: buildConfigContent completed, config size=%d", content.count)
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
        // Priority 0: Injected memory config
        if let injected = self.configContentOverride {
            NSLog("OpenMesh System VPN: Using injected config template")
            return injected
        }
        
        let fileManager = FileManager.default
        
        // Priority 1: App Group shared config
        if let sharedDataDirURL {
            let overrideURL = sharedDataDirURL.appendingPathComponent("singbox_config.json", isDirectory: false)
            if fileManager.fileExists(atPath: overrideURL.path) {
                NSLog("OpenMesh System VPN: Loading config from App Group: %@", overrideURL.path)
                if let content = try? String(contentsOf: overrideURL, encoding: .utf8) {
                    return content
                }
                NSLog("OpenMesh System VPN: Failed to read App Group config, falling back")
            }
        }
        
        // Priority 2: Bundle resource
        if let bundledURL = Bundle.main.url(forResource: "singbox_base_config", withExtension: "json") {
            NSLog("OpenMesh System VPN: Loading config from bundle: %@", bundledURL.path)
            return String(decoding: try Data(contentsOf: bundledURL), as: UTF8.self)
        }
        
        // Priority 3: Hardcoded minimal config
        NSLog("OpenMesh System VPN: WARNING - No config file found, using minimal fallback config")
        return """
        {
          "log": { "level": "info" },
          "inbounds": [{
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.18.0.1/30"],
            "auto_route": true
          }],
          "outbounds": [
            { "type": "direct", "tag": "direct" }
          ],
          "route": {
            "final": "direct",
            "auto_detect_interface": true,
            "rules": []
          }
        }
        """
    }

    private func writeGeneratedConfigSnapshot(_ content: String) throws {
        guard let cacheDirURL else { return }
        let url = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
        guard let data = content.data(using: .utf8) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func startRulesWatcherIfNeeded() throws {
        guard rulesWatcher == nil else { return }
        guard let sharedDataDirURL else { return }
        // Assuming FileSystemWatcher is available
        let watcher = FileSystemWatcher(url: sharedDataDirURL, queue: serviceQueue) { [weak self] in
            self?.scheduleReload(reason: "fs")
        }
        do {
            try watcher.start()
            rulesWatcher = watcher
        } catch {
            NSLog("OpenMesh System VPN WARNING: Failed to start rules watcher (ignoring): %@", error.localizedDescription)
        }
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
        guard let commandServer else { return }
        let override = OMLibboxOverrideOptions()
        override.autoRedirect = false
        do {
            let content = try buildConfigContent()
            NSLog("OpenMesh System VPN reloadService(%@)", reason)
            try commandServer.startOrReloadService(content, options: override)
        } catch {
            NSLog("OpenMesh System VPN reloadService error: %@", String(describing: error))
        }
    }

    private func handleAppMessage0(_ messageData: Data) -> Data? {
        // ... Same basic logic ...
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
                // Basic implementation for System Extension
                guard let sharedDataDirURL else {
                     return #"{"ok":false,"error":"missing sharedDataDirURL"}"#.data(using: .utf8)
                }
                guard let format = dict["format"] as? String, let content = dict["content"] as? String else {
                    return #"{"ok":false,"error":"missing format/content"}"#.data(using: .utf8)
                }
                let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
                if format.lowercased() == "json" {
                     try content.data(using: .utf8)?.write(to: jsonURL, options: [.atomic])
                     scheduleReload(reason: "app_update_rules")
                     return #"{"ok":true}"#.data(using: .utf8)
                }
                return #"{"ok":false}"#.data(using: .utf8)
            default:
                return messageData
            }
        } catch {
            return messageData
        }
    }
}
