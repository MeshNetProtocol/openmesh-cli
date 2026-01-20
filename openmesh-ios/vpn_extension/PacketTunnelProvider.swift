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

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        var err: NSError?
        do {
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

            let setup = OMLibboxSetupOptions()
            setup.basePath = basePath
            setup.workingPath = workingPath
            setup.tempPath = tempPath
            setup.logMaxLines = 2000
            setup.debug = true
            guard OMLibboxSetup(setup, &err) else {
                throw err ?? NSError(domain: "com.openmesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
            }

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

            try server.startOrReloadService(configContent, options: nil as OMLibboxOverrideOptions?)

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
