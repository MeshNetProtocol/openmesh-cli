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

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        var err: NSError?
        do {
            let groupID = "group.com.meshnetprotocol.OpenMesh"
            guard let sharedDir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
                completionHandler(NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing app group container: \(groupID)"]))
                return
            }

            let basePath = sharedDir.path
            let workingPath = sharedDir.appendingPathComponent("work", isDirectory: true).path
            let tempPath = sharedDir.appendingPathComponent("tmp", isDirectory: true).path

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
