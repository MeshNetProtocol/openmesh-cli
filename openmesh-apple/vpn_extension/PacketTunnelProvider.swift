//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/16.
//

import NetworkExtension
import OpenMeshGo

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?

    private func cleanupStaleCommandSocket(in baseDirURL: URL, fileManager: FileManager) {
        let commandSocketURL = baseDirURL.appendingPathComponent("command.sock", isDirectory: false)
        if fileManager.fileExists(atPath: commandSocketURL.path) {
            try? fileManager.removeItem(at: commandSocketURL)
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        var err: NSError?
        do {
            NSLog("OpenMesh VPN extension startTunnel begin")
            let groupID = "group.com.meshnetprotocol.OpenMesh"
            let fileManager = FileManager.default
            let baseDirURL: URL
            if let sharedDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                baseDirURL = sharedDir
            } else if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                baseDirURL = appSupport.appendingPathComponent("OpenMesh", isDirectory: true)
            } else {
                completionHandler(NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing app group container and Application Support directory unavailable"]))
                return
            }

            let basePath = baseDirURL.path
            let workingPath = baseDirURL.appendingPathComponent("work", isDirectory: true).path
            let tempPath = baseDirURL.appendingPathComponent("tmp", isDirectory: true).path

            try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: workingPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
            self.baseDirURL = baseDirURL

            cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)

            let setup = OMLibboxSetupOptions()
            setup.basePath = basePath
            setup.workingPath = workingPath
            setup.tempPath = tempPath
            setup.logMaxLines = 2000
            setup.debug = true
            guard OMLibboxSetup(setup, &err) else {
                throw err ?? NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
            }

            // Capture Go/libbox stderr to a file (helps debugging panics).
            let stderrLogPath = baseDirURL.appendingPathComponent("stderr.log", isDirectory: false).path
            _ = OMLibboxRedirectStderr(stderrLogPath, &err)
            err = nil

            let platform = OpenMeshLibboxPlatformInterface(self)
            let server = OMLibboxNewCommandServer(platform, platform, &err)
            if let err { throw err }
            guard let server else {
                throw NSError(domain: "com.openmesh", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
            }

            platformInterface = platform
            commandServer = server

            try server.start()
            NSLog("OpenMesh VPN extension command server started")

            // TODO: Replace this with config passed from the container app (providerConfiguration / file in App Group).
            let configContent = """
            {
              "log": { "level": "info" },
              "inbounds": [
                { "type": "tun", "tag": "tun-in", "auto_route": true, "strict_route": false }
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
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Handle sleep event if needed
        completionHandler()
    }
    
    override func wake() {
        // Handle wake event if needed
    }
}
