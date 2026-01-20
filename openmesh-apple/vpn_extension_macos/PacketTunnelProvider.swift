//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/18.
//

import NetworkExtension
import OpenMeshGo

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?

    private func prepareBaseDirectories(fileManager: FileManager) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        // Align with sing-box: use App Group container as the shared root.
        let groupID = "group.com.meshnetprotocol.OpenMesh"
        guard let sharedDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container: \(groupID). Check Signing & Capabilities (App Groups) for both the app and the extension."])
        }

        let baseDirURL = sharedDir
        let cacheDirURL = sharedDir
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
        let workingDirURL = cacheDirURL.appendingPathComponent("Working", isDirectory: true)

        // Keep the UNIX socket path within Darwin's `sockaddr_un.sun_path` limit (~104 bytes incl NUL).
        let commandSocketPath = baseDirURL.appendingPathComponent("command.sock", isDirectory: false).path
        let socketBytes = commandSocketPath.utf8.count
        if socketBytes > 103 {
            throw NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "command.sock path too long (\(socketBytes) bytes): \(commandSocketPath)"])
        }

        try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)

        cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)
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
        var err: NSError?
        do {
            let fileManager = FileManager.default
            let prepared = try prepareBaseDirectories(fileManager: fileManager)
            let baseDirURL = prepared.baseDirURL
            let basePath = prepared.basePath
            let workingPath = prepared.workingPath
            let tempPath = prepared.tempPath

            self.baseDirURL = baseDirURL
            NSLog("OpenMesh VPN extension baseDirURL=%@", baseDirURL.path)

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
            let stderrLogPath = (baseDirURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent("stderr.log", isDirectory: false)).path
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

            // NOTE: Passing `nil` options has triggered a Go-side crash in our builds (see .ips backtrace).
            // Use an explicit (empty) override options object instead.
            let override = OMLibboxOverrideOptions()
            override.autoRedirect = false
            try server.startOrReloadService(configContent, options: override)

            completionHandler(nil)
        } catch {
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
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}
