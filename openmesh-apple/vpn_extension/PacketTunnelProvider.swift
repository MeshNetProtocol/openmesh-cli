//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/16.
//

import NetworkExtension
import OpenMeshGo

// Match sing-box structure: PacketTunnelProvider is a thin subclass; logic lives in ExtensionProvider.
class ExtensionProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?

    private func cleanupStaleCommandSocket(in baseDirURL: URL, fileManager: FileManager) {
        let commandSocketURL = baseDirURL.appendingPathComponent("command.sock", isDirectory: false)
        if fileManager.fileExists(atPath: commandSocketURL.path) {
            try? fileManager.removeItem(at: commandSocketURL)
        }
    }

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("OpenMesh VPN extension startTunnel begin")

        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSError?
            do {
                let groupID = "group.com.meshnetprotocol.OpenMesh"
                let fileManager = FileManager.default
                guard let baseDirURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
                    throw NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container: \(groupID). Check Signing & Capabilities (App Groups) for both the app and the extension."])
                }

                let basePath = baseDirURL.path
                let cacheDirURL = baseDirURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Caches", isDirectory: true)
                let workingPath = cacheDirURL.appendingPathComponent("Working", isDirectory: true).path
                let tempPath = cacheDirURL.path

                try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
                try fileManager.createDirectory(atPath: workingPath, withIntermediateDirectories: true)
                self.baseDirURL = baseDirURL

                self.cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)

                let setup = OMLibboxSetupOptions()
                setup.basePath = basePath
                setup.workingPath = workingPath
                setup.tempPath = tempPath
                setup.logMaxLines = 2000
                setup.debug = true
                guard OMLibboxSetup(setup, &err) else {
                    throw err ?? NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
                }

                // Capture Go/libbox stderr to a file inside the App Group cache directory (helps debugging panics).
                let stderrLogPath = cacheDirURL.appendingPathComponent("stderr.log", isDirectory: false).path
                _ = OMLibboxRedirectStderr(stderrLogPath, &err)
                err = nil

                let platform = OpenMeshLibboxPlatformInterface(self)
                let server = OMLibboxNewCommandServer(platform, platform, &err)
                if let err { throw err }
                guard let server else {
                    throw NSError(domain: "com.openmesh", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
                }

                self.platformInterface = platform
                self.commandServer = server

                try server.start()
                NSLog("OpenMesh VPN extension command server started")

                // TODO: Replace this with config passed from the container app (providerConfiguration / file in App Group).
                let configContent = """
                {
                  "log": { "level": "info" },
                  "inbounds": [
                    {
                      "type": "tun",
                      "tag": "tun-in",
                      "auto_route": true,
                      "strict_route": false,
                      "address": [
                        "172.18.0.1/30",
                        "fdfe:dcba:9876::1/126"
                      ]
                    }
                  ],
                  "outbounds": [
                    { "type": "direct", "tag": "direct" }
                  ]
                }
                """

                // NOTE: Passing `nil` options has triggered a Go-side crash in our builds (see macOS .ips backtrace).
                // Use an explicit (empty) override options object instead.
                let override = OMLibboxOverrideOptions()
                override.autoRedirect = false

                NSLog("OpenMesh VPN extension startOrReloadService begin")
                try server.startOrReloadService(configContent, options: override)
                NSLog("OpenMesh VPN extension startOrReloadService done")

                NSLog("OpenMesh VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("OpenMesh VPN extension startTunnel failed: %@", String(describing: error))
                completionHandler(error)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        try? commandServer?.closeService()
        commandServer?.close()
        commandServer = nil
        platformInterface?.reset()
        platformInterface = nil
        if let baseDirURL {
            cleanupStaleCommandSocket(in: baseDirURL, fileManager: .default)
        }
        completionHandler()
    }
    
    override func sleep(completionHandler: @escaping () -> Void) { completionHandler() }
    override func wake() {}
}

final class PacketTunnelProvider: ExtensionProvider {}
