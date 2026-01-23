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
    private var username: String?

    private let serviceQueue = DispatchQueue(label: "com.openmesh.vpn.service.system", qos: .userInitiated)
    private var rulesWatcher: FileSystemWatcher?
    private var pendingReload: DispatchWorkItem?

    // System Extensions run as root, so we must manually construct the path to the user's Group Container.
    // We cannot use FileManager.default.containerURL(...) because it would return the root user's container.
    private func prepareBaseDirectories(fileManager: FileManager, username: String) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        let groupID = "group.com.meshnetprotocol.OpenMesh.macsys"
        
        // Manual path construction for System Extension
        let userGroupContainerURL = URL(fileURLWithPath: "/Users/\(username)/Library/Group Containers/\(groupID)")
        
        // Ensure we can access it (though as root we should match entitlements)
        if !fileManager.fileExists(atPath: userGroupContainerURL.path) {
             // Attempt to create it if it doesn't exist? Usually the App creates it.
             // But we can try creating intermediate directories.
             try fileManager.createDirectory(at: userGroupContainerURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o755,
                .ownerAccountName: username 
             ])
        }

        let baseDirURL = userGroupContainerURL
        let cacheDirURL = baseDirURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
        let workingDirURL = cacheDirURL.appendingPathComponent("Working", isDirectory: true)
        let sharedDataDirURL = baseDirURL.appendingPathComponent("OpenMesh", isDirectory: true)

        let commandSocketPath = baseDirURL.appendingPathComponent("command.sock", isDirectory: false).path
        let socketBytes = commandSocketPath.utf8.count
        if socketBytes > 103 {
            throw NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "command.sock path too long (\(socketBytes) bytes): \(commandSocketPath)"])
        }

        // Create directories with appropriate permissions/ownership if needed.
        // Since we are root, we should be careful about ownership if the user app needs to read them.
        // However, standard creating here might result in root-owned files.
        // For simplicity in this adaptation, we rely on standard creation.
        // In a production System Extension, you often use chown to ensure the user can read/write logs.
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

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("OpenMesh System VPN extension startTunnel begin")
        
        // CRITICAL: Retrieve username passed from the App
        guard let username = options?["username"] as? String else {
            let err = NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing username in start options"])
            NSLog("OpenMesh System VPN Error: %@", err.localizedDescription)
            completionHandler(err)
            return
        }
        self.username = username

        serviceQueue.async {
            var err: NSError?
            do {
                let fileManager = FileManager.default
                // Use the new prepare method with username
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager, username: username)
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
        let template = try loadBaseConfigTemplateContent()
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

        guard let sharedDataDirURL else {
            throw NSError(domain: "com.openmesh", code: 3004, userInfo: [NSLocalizedDescriptionKey: "Missing shared data directory."])
        }

        let mode = readRoutingMode(from: sharedDataDirURL)
        let finalOutbound = (mode == "global") ? "proxy" : "direct"
        route["final"] = finalOutbound
        
        // System Extension specific logging
        NSLog("OpenMesh System VPN: mode=%@ final=%@", mode, finalOutbound)

        let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
        if !FileManager.default.fileExists(atPath: jsonURL.path) {
            NSLog("OpenMesh System VPN: No routing_rules.json found at %@", jsonURL.path)
            // We don't throw here to allow basic start, but log it.
        } else {
             // Assuming DynamicRoutingRules is available in this target or shared code
             do {
                var rules = try DynamicRoutingRules.parseJSON(Data(contentsOf: jsonURL))
                rules.normalize()
                routeRules.append(contentsOf: rules.toSingBoxRouteRules(outboundTag: "proxy"))
             } catch {
                 NSLog("OpenMesh System VPN: Failed to parse routing rules: %@", error.localizedDescription)
             }
        }

        route["rules"] = routeRules
        config["route"] = route

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let content = String(decoding: data, as: UTF8.self)
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
                return String(decoding: try Data(contentsOf: overrideURL), as: UTF8.self)
            }
        }
        
        // Fallback to bundle resource
        if let bundledURL = Bundle.main.url(forResource: "singbox_base_config", withExtension: "json") {
            return String(decoding: try Data(contentsOf: bundledURL), as: UTF8.self)
        }

        throw NSError(domain: "com.openmesh", code: 3003, userInfo: [NSLocalizedDescriptionKey: "Missing bundled singbox_base_config.json"])
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
        try watcher.start()
        rulesWatcher = watcher
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
