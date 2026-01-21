//
//  SingboxConfigStore.swift
//  OpenMesh
//
//  Created by wesley on 2026/1/22.
//

import Foundation

/// Manages the sing-box configuration file in the App Group container.
/// The VPN extension will automatically reload when this file changes.
enum SingboxConfigStore {
    static let appGroupID = "group.com.meshnetprotocol.OpenMesh"
    static let relativeDir = "OpenMesh"
    static let filename = "singbox_config.json"
    
    /// Server configuration model
    struct ServerConfig: Equatable {
        var server: String = ""
        var serverPort: Int = 10086
        var password: String = ""
        var method: String = "aes-256-gcm"
        
        static let supportedMethods = [
            "aes-256-gcm",
            "aes-128-gcm",
            "chacha20-ietf-poly1305",
            "2022-blake3-aes-256-gcm",
            "2022-blake3-aes-128-gcm",
            "2022-blake3-chacha20-poly1305"
        ]
    }
    
    /// Get the App Group directory URL
    static func appGroupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    
    /// Get the config file URL in App Group
    static func configFileURL() -> URL? {
        guard let groupURL = appGroupURL() else { return nil }
        return groupURL
            .appendingPathComponent(relativeDir, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
    
    /// Get the bundled base config URL
    static func bundledConfigURL() -> URL? {
        Bundle.main.url(forResource: "singbox_base_config", withExtension: "json")
    }
    
    /// Read the current configuration, falling back to bundled config if needed
    static func readConfig() -> [String: Any]? {
        let fileManager = FileManager.default
        
        // Try App Group config first
        if let configURL = configFileURL(),
           fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let config = obj as? [String: Any] {
            return config
        }
        
        // Fall back to bundled config
        if let bundledURL = bundledConfigURL(),
           let data = try? Data(contentsOf: bundledURL),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let config = obj as? [String: Any] {
            return config
        }
        
        return nil
    }
    
    /// Extract server configuration from the full config
    static func readServerConfig() -> ServerConfig {
        guard let config = readConfig(),
              let outbounds = config["outbounds"] as? [[String: Any]] else {
            return ServerConfig()
        }
        
        // Find the proxy outbound (type: shadowsocks)
        for outbound in outbounds {
            guard let type = outbound["type"] as? String,
                  type == "shadowsocks" else { continue }
            
            var serverConfig = ServerConfig()
            if let server = outbound["server"] as? String {
                serverConfig.server = server
            }
            if let port = outbound["server_port"] as? Int {
                serverConfig.serverPort = port
            }
            if let password = outbound["password"] as? String {
                serverConfig.password = password
            }
            if let method = outbound["method"] as? String {
                serverConfig.method = method
            }
            return serverConfig
        }
        
        return ServerConfig()
    }
    
    /// Save the server configuration
    static func saveServerConfig(_ serverConfig: ServerConfig) throws {
        let fileManager = FileManager.default
        
        // Read the current full config (or bundled as fallback)
        var config = readConfig() ?? [:]
        
        // Ensure outbounds array exists
        var outbounds = config["outbounds"] as? [[String: Any]] ?? []
        
        // Find and update the shadowsocks outbound
        var foundProxy = false
        for i in 0..<outbounds.count {
            guard let type = outbounds[i]["type"] as? String,
                  type == "shadowsocks" else { continue }
            
            outbounds[i]["server"] = serverConfig.server
            outbounds[i]["server_port"] = serverConfig.serverPort
            outbounds[i]["password"] = serverConfig.password
            outbounds[i]["method"] = serverConfig.method
            foundProxy = true
            break
        }
        
        // If no shadowsocks outbound found, create one
        if !foundProxy {
            let proxyOutbound: [String: Any] = [
                "type": "shadowsocks",
                "tag": "proxy",
                "server": serverConfig.server,
                "server_port": serverConfig.serverPort,
                "password": serverConfig.password,
                "method": serverConfig.method,
                "multiplex": ["enabled": false]
            ]
            outbounds.insert(proxyOutbound, at: 0)
        }
        
        config["outbounds"] = outbounds
        
        // Update route_exclude_address to exclude the server IP
        if var inbounds = config["inbounds"] as? [[String: Any]] {
            for i in 0..<inbounds.count {
                guard let type = inbounds[i]["type"] as? String, type == "tun" else { continue }
                var excludeAddrs = inbounds[i]["route_exclude_address"] as? [String] ?? []
                // Remove old server IPs and add new one
                excludeAddrs = excludeAddrs.filter { !$0.contains("/32") || $0.contains("223.5.5.5") }
                if !serverConfig.server.isEmpty {
                    excludeAddrs.insert("\(serverConfig.server)/32", at: 0)
                }
                inbounds[i]["route_exclude_address"] = excludeAddrs
            }
            config["inbounds"] = inbounds
        }
        
        // Write to App Group
        guard let configURL = configFileURL() else {
            throw NSError(domain: "SingboxConfigStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access App Group container"])
        }
        
        // Ensure directory exists
        let dirURL = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        // Write JSON
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: [.atomic])
    }
}
