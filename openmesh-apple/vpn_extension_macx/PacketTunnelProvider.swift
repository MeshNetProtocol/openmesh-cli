//
//  PacketTunnelProvider.swift
//  meshflux.Sys-ext
//
//  Created by wesley on 2026/1/23.
//

import NetworkExtension
import OpenMeshGo
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var boxService: OMLibboxBoxService?
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
        self.sharedDataDirURL = userGroupContainerURL.appendingPathComponent("MeshFlux", isDirectory: true)
        
        // CRITICAL: Use /var/tmp for runtime files - System Extension has full access here
        // This is different from NSTemporaryDirectory() which may be user-specific
        let baseDirURL = URL(fileURLWithPath: "/var/tmp/meshflux.macsys")
        
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
        
        NSLog("MeshFlux System VPN: basePath=%@ (runtime), sharedDataDir=%@ (config reference)",
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
        NSLog("MeshFlux System VPN extension startTunnel begin")
        NSLog("MeshFlux System VPN extension options keys: %@", String(describing: options?.keys))
        if let proto = self.protocolConfiguration as? NETunnelProviderProtocol {
            NSLog("MeshFlux System VPN: NETunnelProviderProtocol.includeAllNetworks=%@", proto.includeAllNetworks ? "true" : "false")
            if #available(macOS 11.0, *) {
                // best-effort: these fields exist on newer OS versions; log if present
                NSLog("MeshFlux System VPN: NETunnelProviderProtocol.excludeLocalNetworks=%@", proto.excludeLocalNetworks ? "true" : "false")
            }
        } else {
            NSLog("MeshFlux System VPN: protocolConfiguration is not NETunnelProviderProtocol (type=%@)", String(describing: type(of: self.protocolConfiguration)))
        }
        
        // Get providerConfiguration from the saved protocol (this is where main app puts config data)
        let providerConfig = (self.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        NSLog("MeshFlux System VPN: ===== CONFIGURATION INJECTION DEBUG =====")
        NSLog("MeshFlux System VPN: options keys: %@", String(describing: options?.keys))
        NSLog("MeshFlux System VPN: providerConfiguration keys: %@", String(describing: providerConfig?.keys))
        
        if let providerConfig = providerConfig {
            for (key, value) in providerConfig {
                if let strValue = value as? String {
                    let preview = strValue.count > 100 ? String(strValue.prefix(100)) + "..." : strValue
                    NSLog("MeshFlux System VPN: providerConfig[%@] = %@ (len=%d)", key, preview, strValue.count)
                } else {
                    NSLog("MeshFlux System VPN: providerConfig[%@] = %@", key, String(describing: type(of: value)))
                }
            }
        }
        
        // CRITICAL: For System Extensions, startVPNTunnel(options:) may not pass all data.
        // Config content is stored in protocolConfiguration.providerConfiguration.
        // Username comes via startVPNTunnel(options:).
        
        // 1. Get config content from providerConfiguration (primary) or options (fallback)
        if let configStr = providerConfig?["singbox_config_content"] as? String {
            self.configContentOverride = configStr
            NSLog("MeshFlux System VPN: Using config from providerConfiguration (len=%d)", configStr.count)
        } else if let configStr = options?["singbox_config_content"] as? String {
            self.configContentOverride = configStr
            NSLog("MeshFlux System VPN: Using config from options (len=%d)", configStr.count)
        }
        
        // 2. Get routing rules from providerConfiguration (primary) or options (fallback)
        if let rulesStr = providerConfig?["routing_rules_content"] as? String {
            self.rulesContentOverride = rulesStr
            NSLog("MeshFlux System VPN: Using rules from providerConfiguration (len=%d)", rulesStr.count)
        } else if let rulesStr = options?["routing_rules_content"] as? String {
            self.rulesContentOverride = rulesStr
            NSLog("MeshFlux System VPN: Using rules from options (len=%d)", rulesStr.count)
        }
        
        // 3. Get username from options (primary) or providerConfiguration (fallback)
        var finalUsername: String? = nil
        if let username = options?["username"] as? String, !username.isEmpty {
            finalUsername = username
            NSLog("MeshFlux System VPN: Username from options: %@", username)
        } else if let username = providerConfig?["username"] as? String, !username.isEmpty {
            finalUsername = username
            NSLog("MeshFlux System VPN: Username from providerConfiguration: %@", username)
        }
        
        guard let finalUsername = finalUsername else {
            let err = NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "CRITICAL STARTUP FAILURE: Missing 'username' in both options and providerConfiguration."])
            NSLog("%@", err.localizedDescription)
            completionHandler(err)
            return
        }
        self.username = finalUsername
        NSLog("MeshFlux System VPN: Username verified: %@", finalUsername)
        
        // Summary of injected configuration
        NSLog("MeshFlux System VPN: Config injection summary:")
        NSLog("MeshFlux System VPN:   - configContentOverride: %@", self.configContentOverride != nil ? "YES (len=\(self.configContentOverride!.count))" : "NO")
        NSLog("MeshFlux System VPN:   - rulesContentOverride: %@", self.rulesContentOverride != nil ? "YES (len=\(self.rulesContentOverride!.count))" : "NO")
        NSLog("MeshFlux System VPN:   - username: %@", finalUsername)
        if let proto = self.protocolConfiguration as? NETunnelProviderProtocol {
            NSLog("MeshFlux System VPN:   - includeAllNetworks: %@", proto.includeAllNetworks ? "true" : "false")
        }
        NSLog("MeshFlux System VPN: ===== END CONFIGURATION INJECTION DEBUG =====")

        serviceQueue.async {
            var err: NSError?
            do {
                NSLog("MeshFlux System VPN: startTunnel async block started (thread=%@)", Thread.current)
                
                let fileManager = FileManager.default
                // Use the new prepare method with username
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager, username: finalUsername)
                let baseDirURL = prepared.baseDirURL
                let basePath = prepared.basePath
                let workingPath = prepared.workingPath
                let tempPath = prepared.tempPath

                self.baseDirURL = baseDirURL
                NSLog("MeshFlux System VPN: Directories prepared: basePath=%@", basePath)
                NSLog("MeshFlux System VPN extension baseDirURL=%@", baseDirURL.path)

                // Verify App Group Access (Soft Check)
                if let sharedDataDirURL = self.sharedDataDirURL {
                     NSLog("MeshFlux System VPN: Base directory set to %@", sharedDataDirURL.path)
                }

                let setup = OMLibboxSetupOptions()
                setup.basePath = basePath
                setup.workingPath = workingPath
                setup.tempPath = tempPath
                guard OMLibboxSetup(setup, &err) else {
                    throw err ?? NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
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
                let server = OMLibboxNewCommandServer(platform, 2000)
                guard let server else {
                    throw NSError(domain: "com.meshflux", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
                }

                self.platformInterface = platform
                self.commandServer = server

                // Align with sing-box ExtensionProvider: server.start() first, then NewService → service.start() → setService(service).
                try server.start()
                NSLog("MeshFlux System VPN: Command server started successfully")
                NSLog("MeshFlux System VPN extension command server started")
                NSLog("MeshFlux System VPN: ===== CALLING buildConfigContent() =====")
                let configContent = try self.buildConfigContent()
                NSLog("MeshFlux System VPN: ===== buildConfigContent() RETURNED SUCCESSFULLY =====")
                NSLog("MeshFlux System VPN: Received config content length: %d bytes", configContent.count)

                var serviceErr: NSError?
                guard let boxService = OMLibboxNewService(configContent, platform, &serviceErr) else {
                    throw serviceErr ?? NSError(domain: "com.meshflux", code: 4, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewService failed"])
                }
                try boxService.start()
                server.setService(boxService)
                self.boxService = boxService
                NSLog("MeshFlux System VPN: ===== LIBBOX SERVICE STARTED =====")
                
                // Log stderr.log location for debugging
                NSLog("MeshFlux System VPN: Check stderr.log at: %@", stderrLogPath)
                
                // Verify generated config file exists and log key info
                if let cacheDirURL = self.cacheDirURL {
                    let generatedConfigURL = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
                    if FileManager.default.fileExists(atPath: generatedConfigURL.path) {
                        NSLog("MeshFlux System VPN: Generated config exists at: %@", generatedConfigURL.path)
                        if let configData = try? Data(contentsOf: generatedConfigURL),
                           let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
                           let route = configDict["route"] as? [String: Any],
                           let rules = route["rules"] as? [[String: Any]] {
                            NSLog("MeshFlux System VPN: Config verification - route.final=%@, rules.count=%d",
                                  route["final"] as? String ?? "nil", rules.count)
                            if let domainSuffixRule = rules.first(where: { $0["domain_suffix"] != nil }) {
                                let suffixes = domainSuffixRule["domain_suffix"] as? [String] ?? []
                                let xcomCount = suffixes.filter { $0.contains("x.com") }.count
                                let twimgCount = suffixes.filter { $0.contains("twimg") }.count
                                NSLog("MeshFlux System VPN: Config verification - x.com entries=%d, twimg entries=%d", xcomCount, twimgCount)
                            }
                        }
                    }
                }

                try self.startRulesWatcherIfNeeded()

                // Log completion with detailed timing
                let completionTime = Date()
                NSLog("MeshFlux System VPN: [COMPLETION] startTunnel about to call completionHandler (thread=%@, t=%f)", Thread.current, completionTime.timeIntervalSince1970)
                NSLog("MeshFlux System VPN: [COMPLETION] commandServer=%@, platformInterface=%@",
                      self.commandServer != nil ? "present" : "nil",
                      self.platformInterface != nil ? "present" : "nil")
                NSLog("MeshFlux System VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
                let afterCompletionTime = Date()
                NSLog("MeshFlux System VPN: [COMPLETION] completionHandler called (duration=%.3f seconds)", afterCompletionTime.timeIntervalSince(completionTime))
            } catch {
                NSLog("MeshFlux System VPN: ERROR - startTunnel failed: %@", String(describing: error))
                NSLog("MeshFlux System VPN extension startTunnel failed: %@", String(describing: error))
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
        // Align with sing-box ExtensionProvider: pause box service when system sleeps.
        boxService?.pause()
        completionHandler()
    }

    override func wake() {
        // Align with sing-box ExtensionProvider: resume box service when system wakes.
        boxService?.wake()
    }

    // MARK: - Dynamic Rules and Logic (Copied from App Extension)

    private func buildConfigContent() throws -> String {
        NSLog("MeshFlux System VPN: buildConfigContent started")
        NSLog("MeshFlux System VPN: sharedDataDirURL=%@", sharedDataDirURL?.path ?? "nil")
        NSLog("MeshFlux System VPN: cacheDirURL=%@", cacheDirURL?.path ?? "nil")
        
        let template = try loadBaseConfigTemplateContent()
        NSLog("MeshFlux System VPN: Loaded base config template, length=%d", template.count)
        
        let obj = try JSONSerialization.jsonObject(with: Data(template.utf8), options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else {
            throw NSError(domain: "com.meshflux", code: 3001, userInfo: [NSLocalizedDescriptionKey: "base config template is not a JSON object"])
        }

        // System Extension build may not include gVisor.
        // When includeAllNetworks=true, sing-box/libbox may prefer gVisor stack for TUN.
        // Force the TUN inbound to use the system stack to avoid hard failure:
        // "gVisor is not included in this build, rebuild with -tags with_gvisor".
        if var inbounds = config["inbounds"] as? [[String: Any]] {
            var forcedCount = 0
            for i in inbounds.indices {
                guard let type = inbounds[i]["type"] as? String, type == "tun" else { continue }
                let oldStack = inbounds[i]["stack"] as? String
                if oldStack != "system" {
                    inbounds[i]["stack"] = "system"
                    forcedCount += 1
                    NSLog("MeshFlux System VPN: Forced inbound/tun stack=system (old=%@, tag=%@)",
                          oldStack ?? "nil",
                          (inbounds[i]["tag"] as? String) ?? "nil")
                }
            }
            if forcedCount > 0 {
                config["inbounds"] = inbounds
                NSLog("MeshFlux System VPN: Forced stack=system for %d tun inbound(s)", forcedCount)
            }
        }

        guard var route = config["route"] as? [String: Any] else {
            throw NSError(domain: "com.meshflux", code: 3002, userInfo: [NSLocalizedDescriptionKey: "base config missing route section"])
        }

        // System Extension runs as root with restricted network; remote rule-set (geoip-cn) download
        // can hang or fail and block boxService.start(). Use bundled geoip-cn.srs when present,
        // otherwise remove the rule-set so startup does not block.
        if var ruleSet = route["rule_set"] as? [[String: Any]] {
            if let geoipIndex = ruleSet.firstIndex(where: { ($0["tag"] as? String) == "geoip-cn" && ($0["type"] as? String) == "remote" }) {
                let bundledPath: String? = Bundle.main.path(forResource: "geoip-cn", ofType: "srs")
                if let path = bundledPath, FileManager.default.fileExists(atPath: path) {
                    ruleSet[geoipIndex] = [
                        "type": "local",
                        "tag": "geoip-cn",
                        "format": "binary",
                        "path": path
                    ]
                    route["rule_set"] = ruleSet
                    config["route"] = route
                    NSLog("MeshFlux System VPN: Replaced remote geoip-cn rule-set with bundled local path: %@", path)
                } else {
                    ruleSet.remove(at: geoipIndex)
                    route["rule_set"] = ruleSet.isEmpty ? nil : ruleSet
                    config["route"] = route
                    // Remove route_exclude_address_set reference to geoip-cn so we don't reference a missing rule-set
                    if var inbounds = config["inbounds"] as? [[String: Any]] {
                        for i in inbounds.indices {
                            if var excludeSet = inbounds[i]["route_exclude_address_set"] as? [String],
                               let idx = excludeSet.firstIndex(of: "geoip-cn") {
                                excludeSet.remove(at: idx)
                                inbounds[i]["route_exclude_address_set"] = excludeSet.isEmpty ? nil : excludeSet
                                config["inbounds"] = inbounds
                                break
                            }
                        }
                    }
                    NSLog("MeshFlux System VPN: geoip-cn.srs not in bundle; removed remote rule-set and route_exclude_address_set reference to avoid startup hang (CN IPs may go through TUN)")
                }
            }
        }

        var routeRules: [[String: Any]] = []
        if let existing = route["rules"] as? [Any] {
            for item in existing {
                if let dict = item as? [String: Any] {
                    routeRules.append(dict)
                }
            }
        }
        NSLog("MeshFlux System VPN: Existing route rules count=%d", routeRules.count)

        guard let sharedDataDirURL else {
            throw NSError(domain: "com.meshflux", code: 3004, userInfo: [NSLocalizedDescriptionKey: "Missing shared data directory."])
        }

        let finalOutbound = (route["final"] as? String) ?? "proxy"
        route["final"] = finalOutbound
        
        NSLog("MeshFlux System VPN: raw profile mode final=%@", finalOutbound)

        // CRITICAL FIX: Insert domain rules BEFORE sniff rule
        // Rule order matters! Domain-specific rules must come before generic sniff rules.
        // Current order: [sniff, hijack-dns] + [domain_suffix]
        // Correct order: [domain_suffix, sniff, hijack-dns]
        // This ensures domain matching happens before sniffing.
        
        var domainRules: [[String: Any]] = []
        
        // Try memory-injected rules first
        if let rulesStr = self.rulesContentOverride {
            NSLog("MeshFlux System VPN: Using injected routing rules (len=%d)", rulesStr.count)
            do {
                guard let rulesData = rulesStr.data(using: .utf8) else { throw NSError(domain: "UTF8", code: 0) }
                var rules = try DynamicRoutingRules.parseJSON(rulesData)
                rules.normalize()
                let newRules = rules.toSingBoxRouteRules(outboundTag: "proxy")
                NSLog("MeshFlux System VPN: Parsed %d dynamic rules from injection", newRules.count)
                domainRules = newRules
            } catch {
                NSLog("MeshFlux System VPN: Failed to parse injected routing rules: %@", error.localizedDescription)
            }
        } else {
            // Fallback to file reading
            let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                NSLog("MeshFlux System VPN: Found routing_rules.json at %@", jsonURL.path)
                do {
                    let rulesData = try Data(contentsOf: jsonURL)
                    NSLog("MeshFlux System VPN: routing_rules.json size=%d bytes", rulesData.count)
                    var rules = try DynamicRoutingRules.parseJSON(rulesData)
                    rules.normalize()
                    let newRules = rules.toSingBoxRouteRules(outboundTag: "proxy")
                    NSLog("MeshFlux System VPN: Parsed %d dynamic rules from file", newRules.count)
                    domainRules = newRules
                } catch {
                    NSLog("MeshFlux System VPN: Failed to parse routing rules file: %@", error.localizedDescription)
                }
            } else {
                NSLog("MeshFlux System VPN: No routing_rules.json found (and no injection)")
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
            NSLog("MeshFlux System VPN: ADDED missing sniff rule at position 0")
        }
        
        // Insert domain rules right after sniff
        routeRules.insert(contentsOf: domainRules, at: sniffIndex + 1)
        NSLog("MeshFlux System VPN: Inserted %d domain rules after sniff (at position %d). Total rules now: %d", domainRules.count, sniffIndex + 1, routeRules.count)

        route["rules"] = routeRules
        config["route"] = route
        
        // Enable debug logging to track domain matching
        // This will help us see which domains match rules and which don't
        var logConfig = config["log"] as? [String: Any] ?? [:]
        logConfig["level"] = "debug"
        logConfig["timestamp"] = true
        // Add log output file for domain matching tracking (sing-box expects a string path, not array)
        let logFilePath = cacheDirURL?.appendingPathComponent("route_match.log", isDirectory: false).path ?? "/tmp/meshflux_route_match.log"
        logConfig["output"] = logFilePath
        config["log"] = logConfig
        NSLog("MeshFlux System VPN: Enabled debug logging, log output: %@", logFilePath)
        
        // COMPREHENSIVE DEBUG: Log all route rules in detail
        NSLog("MeshFlux System VPN: ===== ROUTE CONFIGURATION DEBUG =====")
        NSLog("MeshFlux System VPN: Route final outbound: %@", finalOutbound)
        NSLog("MeshFlux System VPN: Total route rules: %d", routeRules.count)
        
        for (index, rule) in routeRules.enumerated() {
            let ruleKeys = Array(rule.keys).sorted()
            NSLog("MeshFlux System VPN: Rule[%d] keys: %@", index, ruleKeys.joined(separator: ", "))
            
            // Log domain_suffix details
            if let domainSuffix = rule["domain_suffix"] as? [String] {
                let xcomSuffixes = domainSuffix.filter { $0.contains("x.com") }
                let facebookSuffixes = domainSuffix.filter { $0.contains("facebook") || $0.contains("fb.com") }
                let twimgSuffixes = domainSuffix.filter { $0.contains("twimg") }
                let twitterSuffixes = domainSuffix.filter { $0.contains("twitter") }
                
                NSLog("MeshFlux System VPN: Rule[%d] domain_suffix count: %d", index, domainSuffix.count)
                if !xcomSuffixes.isEmpty {
                    NSLog("MeshFlux System VPN: Rule[%d] x.com suffixes: %@", index, xcomSuffixes.joined(separator: ", "))
                }
                if !facebookSuffixes.isEmpty {
                    NSLog("MeshFlux System VPN: Rule[%d] facebook suffixes: %@", index, facebookSuffixes.joined(separator: ", "))
                }
                if !twimgSuffixes.isEmpty {
                    NSLog("MeshFlux System VPN: Rule[%d] twimg suffixes: %@", index, twimgSuffixes.joined(separator: ", "))
                }
                if !twitterSuffixes.isEmpty {
                    NSLog("MeshFlux System VPN: Rule[%d] twitter suffixes: %@", index, twitterSuffixes.joined(separator: ", "))
                }
            }
            
            // Log domain details
            if let domain = rule["domain"] as? [String] {
                let xcomDomains = domain.filter { $0.contains("x.com") }
                if !xcomDomains.isEmpty {
                    NSLog("MeshFlux System VPN: Rule[%d] x.com domains: %@", index, xcomDomains.joined(separator: ", "))
                }
            }
            
            // Log outbound
            if let outbound = rule["outbound"] as? String {
                NSLog("MeshFlux System VPN: Rule[%d] outbound: %@", index, outbound)
            }
            
            // Log action
            if let action = rule["action"] as? String {
                NSLog("MeshFlux System VPN: Rule[%d] action: %@", index, action)
            }
        }
        
        // Log DNS configuration
        if let dns = config["dns"] as? [String: Any] {
            NSLog("MeshFlux System VPN: DNS config present")
            if let servers = dns["servers"] as? [[String: Any]] {
                NSLog("MeshFlux System VPN: DNS servers count: %d", servers.count)
                for (idx, server) in servers.enumerated() {
                    if let tag = server["tag"] as? String {
                        NSLog("MeshFlux System VPN: DNS server[%d] tag: %@", idx, tag)
                    }
                }
            }
        }
        
        // Log outbounds
        if let outbounds = config["outbounds"] as? [[String: Any]] {
            NSLog("MeshFlux System VPN: Outbounds count: %d", outbounds.count)
            for (idx, outbound) in outbounds.enumerated() {
                if let tag = outbound["tag"] as? String {
                    NSLog("MeshFlux System VPN: Outbound[%d] tag: %@", idx, tag)
                }
            }
        }
        
        NSLog("MeshFlux System VPN: ===== END ROUTE CONFIGURATION DEBUG =====")
        
        NSLog("MeshFlux System VPN: Final route rules count=%d, final outbound=%@", routeRules.count, finalOutbound)

        NSLog("MeshFlux System VPN: Serializing config to JSON")
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        NSLog("MeshFlux System VPN: JSON serialization successful, size=%d bytes", data.count)
        var content = String(decoding: data, as: UTF8.self)
        content = applyRoutingModeToConfigContent(content, isGlobalMode: false)
        NSLog("MeshFlux System VPN: Applied raw profile mode patch, length=%d", content.count)
        try writeGeneratedConfigSnapshot(content)
        NSLog("MeshFlux System VPN: Config snapshot written")
        
        // DEBUG: Write route section to separate file for easy inspection
        if let routeData = try? JSONSerialization.data(withJSONObject: route, options: [.prettyPrinted, .sortedKeys]),
           let routeStr = String(data: routeData, encoding: .utf8) {
            let routeDebugURL = cacheDirURL?.appendingPathComponent("route_config_debug.json", isDirectory: false)
            if let routeDebugURL = routeDebugURL {
                try? routeStr.write(to: routeDebugURL, atomically: true, encoding: .utf8)
                NSLog("MeshFlux System VPN: Route config written to: %@", routeDebugURL.path)
            }
        }
        
        // DEBUG: Write a debug log file to track injection state (non-blocking)
        do {
            try writeDebugLog([
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
            NSLog("MeshFlux System VPN: Debug log written successfully")
        } catch {
            NSLog("MeshFlux System VPN: WARNING - Failed to write debug log (non-critical): %@", error.localizedDescription)
        }
        
        NSLog("MeshFlux System VPN: ===== BUILD CONFIG CONTENT COMPLETED SUCCESSFULLY =====")
        NSLog("MeshFlux System VPN: Final config size: %d bytes", content.count)
        NSLog("MeshFlux System VPN: Final route rules count: %d", routeRules.count)
        NSLog("MeshFlux System VPN: Final outbound: %@", finalOutbound)
        NSLog("MeshFlux System VPN: Returning config content to caller")
        return content
    }

    private func loadBaseConfigTemplateContent() throws -> String {
        // Priority 0: Injected memory config
        if let injected = self.configContentOverride {
            NSLog("MeshFlux System VPN: Using injected config template")
            return injected
        }
        
        let fileManager = FileManager.default
        
        // Priority 1: App Group shared config
        if let sharedDataDirURL {
            let overrideURL = sharedDataDirURL.appendingPathComponent("singbox_config.json", isDirectory: false)
            if fileManager.fileExists(atPath: overrideURL.path) {
                NSLog("MeshFlux System VPN: Loading config from App Group: %@", overrideURL.path)
                // STRICT MODE: Fail if unreadable
                return try String(contentsOf: overrideURL, encoding: .utf8)
            } else {
                 throw NSError(domain: "com.meshflux", code: 3999, userInfo: [NSLocalizedDescriptionKey: "CRITICAL: singbox_config.json NOT FOUND in App Group: \(overrideURL.path)"])
            }
        }
        
        throw NSError(domain: "com.meshflux", code: 4000, userInfo: [NSLocalizedDescriptionKey: "CRITICAL: sharedDataDirURL is nil during config loading"])
    }

    private func writeGeneratedConfigSnapshot(_ content: String) throws {
        guard let cacheDirURL else { return }
        let url = cacheDirURL.appendingPathComponent("generated_config.json", isDirectory: false)
        guard let data = content.data(using: .utf8) else { return }
        try? data.write(to: url, options: [.atomic])
    }
    
    // DEBUG HELPER: Write debug info to a file that can be inspected
    private func writeDebugLog(_ info: [String: Any]) throws {
        // CRITICAL: Use /tmp (root-accessible) as PRIMARY location
        // System Extension may not have reliable access to user's App Group
        let primaryURL = URL(fileURLWithPath: "/tmp/meshflux_sys_debug.json")
        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: primaryURL, options: [.atomic])
        
        // Try App Group as SECONDARY (may fail silently)
        if let sharedDataDirURL = sharedDataDirURL {
            let debugURL = sharedDataDirURL.appendingPathComponent("debug_log.json", isDirectory: false)
            try? data.write(to: debugURL, options: [.atomic])
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
            NSLog("MeshFlux System VPN WARNING: Failed to start rules watcher (ignoring): %@", error.localizedDescription)
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
        guard let commandServer, let platform = platformInterface else { return }
        do {
            NSLog("MeshFlux System VPN reloadService(%@)", reason)
            // Align with sing-box: stopService (close old, setService(nil)) then startService (NewService, start, setService).
            try? boxService?.close()
            commandServer.setService(nil)
            boxService = nil
            let content = try buildConfigContent()
            var serviceErr: NSError?
            guard let newService = OMLibboxNewService(content, platform, &serviceErr) else {
                NSLog("MeshFlux System VPN reloadService error: %@", String(describing: serviceErr))
                return
            }
            try newService.start()
            commandServer.setService(newService)
            boxService = newService
        } catch {
            NSLog("MeshFlux System VPN reloadService error: %@", String(describing: error))
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
