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

    // System Extensions run as root but in a restricted sandbox.
    // Even with correct POSIX permissions, root may not access user directories.
    // Solution: Use /var/tmp for runtime files (basePath), inject config via providerConfiguration.
    private func prepareBaseDirectories(fileManager: FileManager, username: String) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        let groupID = "group.com.meshnetprotocol.OpenMesh.macsys"
        
        // sharedDataDirURL = user's App Group (for reference, but we don't rely on file access)
        let userGroupContainerURL = URL(fileURLWithPath: "/Users/\(username)/Library/Group Containers/\(groupID)")
        self.sharedDataDirURL = userGroupContainerURL.appendingPathComponent("OpenMesh", isDirectory: true)
        
        // CRITICAL: Use /var/tmp for runtime files - System Extension has full access here
        // This is different from NSTemporaryDirectory() which may be user-specific
        let baseDirURL = URL(fileURLWithPath: "/var/tmp/OpenMesh.macsys")
        
        let cacheDirURL = baseDirURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            
        let workingDirURL = cacheDirURL.appendingPathComponent("Working", isDirectory: true)
        
        self.cacheDirURL = cacheDirURL

        // Create directories (System Extension running as root has access to /var/tmp)
        try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)

        // Cleanup stale socket
        cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)
        
        NSLog("OpenMesh System VPN: basePath=%@ (runtime), sharedDataDir=%@ (config reference)", 
              baseDirURL.path, self.sharedDataDirURL?.path ?? "nil")

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
        NSLog("OpenMesh System VPN extension options keys: %@", String(describing: options?.keys))
        
        // Get providerConfiguration from the saved protocol (this is where main app puts config data)
        let providerConfig = (self.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        NSLog("OpenMesh System VPN: ===== CONFIGURATION INJECTION DEBUG =====")
        NSLog("OpenMesh System VPN: options keys: %@", String(describing: options?.keys))
        NSLog("OpenMesh System VPN: providerConfiguration keys: %@", String(describing: providerConfig?.keys))
        
        if let providerConfig = providerConfig {
            for (key, value) in providerConfig {
                if let strValue = value as? String {
                    let preview = strValue.count > 100 ? String(strValue.prefix(100)) + "..." : strValue
                    NSLog("OpenMesh System VPN: providerConfig[%@] = %@ (len=%d)", key, preview, strValue.count)
                } else {
                    NSLog("OpenMesh System VPN: providerConfig[%@] = %@", key, String(describing: type(of: value)))
                }
            }
        }
        
        // CRITICAL: For System Extensions, startVPNTunnel(options:) may not pass all data.
        // Config content is stored in protocolConfiguration.providerConfiguration.
        // Username comes via startVPNTunnel(options:).
        
        // 1. Get config content from providerConfiguration (primary) or options (fallback)
        if let configStr = providerConfig?["singbox_config_content"] as? String {
            self.configContentOverride = configStr
            NSLog("OpenMesh System VPN: Using config from providerConfiguration (len=%d)", configStr.count)
        } else if let configStr = options?["singbox_config_content"] as? String {
            self.configContentOverride = configStr
            NSLog("OpenMesh System VPN: Using config from options (len=%d)", configStr.count)
        }
        
        // 2. Get routing rules from providerConfiguration (primary) or options (fallback)
        if let rulesStr = providerConfig?["routing_rules_content"] as? String {
            self.rulesContentOverride = rulesStr
            NSLog("OpenMesh System VPN: Using rules from providerConfiguration (len=%d)", rulesStr.count)
        } else if let rulesStr = options?["routing_rules_content"] as? String {
            self.rulesContentOverride = rulesStr
            NSLog("OpenMesh System VPN: Using rules from options (len=%d)", rulesStr.count)
        }
        
        // 3. Get username from options (primary) or providerConfiguration (fallback)
        var finalUsername: String? = nil
        if let username = options?["username"] as? String, !username.isEmpty {
            finalUsername = username
            NSLog("OpenMesh System VPN: Username from options: %@", username)
        } else if let username = providerConfig?["username"] as? String, !username.isEmpty {
            finalUsername = username
            NSLog("OpenMesh System VPN: Username from providerConfiguration: %@", username)
        }
        
        guard let finalUsername = finalUsername else {
            let err = NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "CRITICAL STARTUP FAILURE: Missing 'username' in both options and providerConfiguration."])
            NSLog("%@", err.localizedDescription)
            completionHandler(err)
            return
        }
        self.username = finalUsername
        NSLog("OpenMesh System VPN: Username verified: %@", finalUsername)
        
        // Summary of injected configuration
        NSLog("OpenMesh System VPN: Config injection summary:")
        NSLog("OpenMesh System VPN:   - configContentOverride: %@", self.configContentOverride != nil ? "YES (len=\(self.configContentOverride!.count))" : "NO")
        NSLog("OpenMesh System VPN:   - rulesContentOverride: %@", self.rulesContentOverride != nil ? "YES (len=\(self.rulesContentOverride!.count))" : "NO")
        NSLog("OpenMesh System VPN:   - username: %@", finalUsername)
        NSLog("OpenMesh System VPN: ===== END CONFIGURATION INJECTION DEBUG =====")

        serviceQueue.async {
            var err: NSError?
            do {
                self.appendDebugEntry("startTunnel async block started")
                
                let fileManager = FileManager.default
                // Use the new prepare method with username
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager, username: finalUsername)
                let baseDirURL = prepared.baseDirURL
                let basePath = prepared.basePath
                let workingPath = prepared.workingPath
                let tempPath = prepared.tempPath

                self.baseDirURL = baseDirURL
                self.appendDebugEntry("Directories prepared: basePath=\(basePath), workingPath=\(workingPath), tempPath=\(tempPath)")
                NSLog("OpenMesh System VPN extension baseDirURL=%@", baseDirURL.path)

                // Verify App Group Access (Soft Check)
                if let sharedDataDirURL = self.sharedDataDirURL {
                     NSLog("OpenMesh System VPN: Base directory set to %@", sharedDataDirURL.path)
                }

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
                self.appendDebugEntry("Command server started successfully")
                NSLog("OpenMesh System VPN extension command server started")

                let configContent = try self.buildConfigContent()
                self.appendDebugEntry("Config built successfully, size=\(configContent.count)")
                NSLog("OpenMesh System VPN: Config content length: %d bytes", configContent.count)

                let override = OMLibboxOverrideOptions()
                override.autoRedirect = false

                NSLog("OpenMesh System VPN: ===== STARTING LIBBOX SERVICE =====")
                NSLog("OpenMesh System VPN: basePath: %@", basePath)
                NSLog("OpenMesh System VPN: workingPath: %@", workingPath)
                NSLog("OpenMesh System VPN: tempPath: %@", tempPath)
                NSLog("OpenMesh System VPN: stderr.log path: %@", stderrLogPath)
                
                self.appendDebugEntry("Calling startOrReloadService...")
                NSLog("OpenMesh System VPN extension startOrReloadService begin")
                try server.startOrReloadService(configContent, options: override)
                self.appendDebugEntry("startOrReloadService completed successfully")
                NSLog("OpenMesh System VPN extension startOrReloadService done")
                NSLog("OpenMesh System VPN: ===== LIBBOX SERVICE STARTED =====")
                
                // Log stderr.log location for debugging
                NSLog("OpenMesh System VPN: Check stderr.log at: %@", stderrLogPath)
                
                // Verify generated config file exists and log key info
                if let cacheDirURL = self.cacheDirURL {
                    let generatedConfigURL = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
                    if FileManager.default.fileExists(atPath: generatedConfigURL.path) {
                        NSLog("OpenMesh System VPN: Generated config exists at: %@", generatedConfigURL.path)
                        if let configData = try? Data(contentsOf: generatedConfigURL),
                           let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
                           let route = configDict["route"] as? [String: Any],
                           let rules = route["rules"] as? [[String: Any]] {
                            NSLog("OpenMesh System VPN: Config verification - route.final=%@, rules.count=%d", 
                                  route["final"] as? String ?? "nil", rules.count)
                            if let domainSuffixRule = rules.first(where: { $0["domain_suffix"] != nil }) {
                                let suffixes = domainSuffixRule["domain_suffix"] as? [String] ?? []
                                let xcomCount = suffixes.filter { $0.contains("x.com") }.count
                                let twimgCount = suffixes.filter { $0.contains("twimg") }.count
                                NSLog("OpenMesh System VPN: Config verification - x.com entries=%d, twimg entries=%d", xcomCount, twimgCount)
                            }
                        }
                    }
                }

                try self.startRulesWatcherIfNeeded()

                NSLog("OpenMesh System VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                self.appendDebugEntry("ERROR: startTunnel failed: \(error.localizedDescription)")
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
        
        // Enable debug logging to track domain matching
        // This will help us see which domains match rules and which don't
        var logConfig = config["log"] as? [String: Any] ?? [:]
        logConfig["level"] = "debug"
        logConfig["timestamp"] = true
        // Add log output file for domain matching tracking (sing-box expects a string path, not array)
        let logFilePath = cacheDirURL?.appendingPathComponent("route_match.log", isDirectory: false).path ?? "/tmp/openmesh_route_match.log"
        logConfig["output"] = logFilePath
        config["log"] = logConfig
        NSLog("OpenMesh System VPN: Enabled debug logging, log output: %@", logFilePath)
        appendDebugEntry("Debug logging enabled, log file: \(logFilePath)")
        
        // COMPREHENSIVE DEBUG: Log all route rules in detail
        NSLog("OpenMesh System VPN: ===== ROUTE CONFIGURATION DEBUG =====")
        NSLog("OpenMesh System VPN: Route final outbound: %@", finalOutbound)
        NSLog("OpenMesh System VPN: Total route rules: %d", routeRules.count)
        
        for (index, rule) in routeRules.enumerated() {
            let ruleKeys = Array(rule.keys).sorted()
            NSLog("OpenMesh System VPN: Rule[%d] keys: %@", index, ruleKeys.joined(separator: ", "))
            
            // Log domain_suffix details
            if let domainSuffix = rule["domain_suffix"] as? [String] {
                let xcomSuffixes = domainSuffix.filter { $0.contains("x.com") }
                let facebookSuffixes = domainSuffix.filter { $0.contains("facebook") || $0.contains("fb.com") }
                let twimgSuffixes = domainSuffix.filter { $0.contains("twimg") }
                let twitterSuffixes = domainSuffix.filter { $0.contains("twitter") }
                
                NSLog("OpenMesh System VPN: Rule[%d] domain_suffix count: %d", index, domainSuffix.count)
                if !xcomSuffixes.isEmpty {
                    NSLog("OpenMesh System VPN: Rule[%d] x.com suffixes: %@", index, xcomSuffixes.joined(separator: ", "))
                }
                if !facebookSuffixes.isEmpty {
                    NSLog("OpenMesh System VPN: Rule[%d] facebook suffixes: %@", index, facebookSuffixes.joined(separator: ", "))
                }
                if !twimgSuffixes.isEmpty {
                    NSLog("OpenMesh System VPN: Rule[%d] twimg suffixes: %@", index, twimgSuffixes.joined(separator: ", "))
                }
                if !twitterSuffixes.isEmpty {
                    NSLog("OpenMesh System VPN: Rule[%d] twitter suffixes: %@", index, twitterSuffixes.joined(separator: ", "))
                }
            }
            
            // Log domain details
            if let domain = rule["domain"] as? [String] {
                let xcomDomains = domain.filter { $0.contains("x.com") }
                if !xcomDomains.isEmpty {
                    NSLog("OpenMesh System VPN: Rule[%d] x.com domains: %@", index, xcomDomains.joined(separator: ", "))
                }
            }
            
            // Log outbound
            if let outbound = rule["outbound"] as? String {
                NSLog("OpenMesh System VPN: Rule[%d] outbound: %@", index, outbound)
            }
            
            // Log action
            if let action = rule["action"] as? String {
                NSLog("OpenMesh System VPN: Rule[%d] action: %@", index, action)
            }
        }
        
        // Log DNS configuration
        if let dns = config["dns"] as? [String: Any] {
            NSLog("OpenMesh System VPN: DNS config present")
            if let servers = dns["servers"] as? [[String: Any]] {
                NSLog("OpenMesh System VPN: DNS servers count: %d", servers.count)
                for (idx, server) in servers.enumerated() {
                    if let tag = server["tag"] as? String {
                        NSLog("OpenMesh System VPN: DNS server[%d] tag: %@", idx, tag)
                    }
                }
            }
        }
        
        // Log outbounds
        if let outbounds = config["outbounds"] as? [[String: Any]] {
            NSLog("OpenMesh System VPN: Outbounds count: %d", outbounds.count)
            for (idx, outbound) in outbounds.enumerated() {
                if let tag = outbound["tag"] as? String {
                    NSLog("OpenMesh System VPN: Outbound[%d] tag: %@", idx, tag)
                }
            }
        }
        
        NSLog("OpenMesh System VPN: ===== END ROUTE CONFIGURATION DEBUG =====")
        
        appendDebugEntry("Final route rules count=\(routeRules.count), final outbound=\(finalOutbound)")
        NSLog("OpenMesh System VPN: Final route rules count=%d", routeRules.count)

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let content = String(decoding: data, as: UTF8.self)
        try writeGeneratedConfigSnapshot(content)
        
        // DEBUG: Write route section to separate file for easy inspection
        if let routeData = try? JSONSerialization.data(withJSONObject: route, options: [.prettyPrinted, .sortedKeys]),
           let routeStr = String(data: routeData, encoding: .utf8) {
            let routeDebugURL = cacheDirURL?.appendingPathComponent("route_config_debug.json", isDirectory: false)
            if let routeDebugURL = routeDebugURL {
                try? routeStr.write(to: routeDebugURL, atomically: true, encoding: .utf8)
                NSLog("OpenMesh System VPN: Route config written to: %@", routeDebugURL.path)
            }
        }
        
        // DEBUG: Write a debug log file to track injection state
        writeDebugLog([
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "rulesContentOverride_present": (self.rulesContentOverride != nil),
            "rulesContentOverride_length": self.rulesContentOverride?.count ?? 0,
            "configContentOverride_present": (self.configContentOverride != nil),
            "configContentOverride_length": self.configContentOverride?.count ?? 0,
            "final_route_rules_count": routeRules.count,
            "route_final_outbound": finalOutbound,
            "sharedDataDirURL": sharedDataDirURL.path,
            "config_size": content.count
        ])
        
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
                // STRICT MODE: Fail if unreadable
                return try String(contentsOf: overrideURL, encoding: .utf8)
            } else {
                 throw NSError(domain: "com.openmesh", code: 3999, userInfo: [NSLocalizedDescriptionKey: "CRITICAL: singbox_config.json NOT FOUND in App Group: \(overrideURL.path)"])
            }
        }
        
        throw NSError(domain: "com.openmesh", code: 4000, userInfo: [NSLocalizedDescriptionKey: "CRITICAL: sharedDataDirURL is nil during config loading"])
    }

    private func writeGeneratedConfigSnapshot(_ content: String) throws {
        guard let cacheDirURL else { return }
        let url = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
        guard let data = content.data(using: .utf8) else { return }
        try? data.write(to: url, options: [.atomic])
    }
    
    // DEBUG HELPER: Write debug info to a file that can be inspected
    private func writeDebugLog(_ info: [String: Any]) {
        // Write to user's App Group where we have read/write access
        guard let sharedDataDirURL else { return }
        let debugURL = sharedDataDirURL.appendingPathComponent("debug_log.json", isDirectory: false)
        do {
            let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: debugURL, options: [.atomic])
        } catch {
            // Also try /tmp as fallback (root has access)
            let fallbackURL = URL(fileURLWithPath: "/tmp/openmesh_sys_debug.json")
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]) {
                try? data.write(to: fallbackURL, options: [.atomic])
            }
        }
    }
    
    // Extended debug: Append log entries to a file
    private func appendDebugEntry(_ message: String) {
        guard let username = self.username else { return }
        let logPath = "/Users/\(username)/Library/Group Containers/group.com.meshnetprotocol.OpenMesh.macsys/OpenMesh/sys_ext_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        
        let fileURL = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            // Create file if it doesn't exist
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
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
