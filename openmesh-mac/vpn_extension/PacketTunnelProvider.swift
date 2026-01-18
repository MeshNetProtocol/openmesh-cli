//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/18.
//

import NetworkExtension
import OpenMeshGo

class PacketTunnelProvider: NEPacketTunnelProvider {

    // Declare Go library instance per Go-Swift integration规范
    private var omOpenmeshAppLib: OMOpenmeshAppLib!

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Correctly initialize Go library instance
        omOpenmeshAppLib = OMOpenmeshAppLib()
        
        // Check if initialization succeeded
        guard omOpenmeshAppLib != nil else {
            completionHandler(NSError(domain: "com.openmesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Go library"]))
            return
        }
        
        // Create tunnel network settings
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        
        // Configure IPv4 settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.10.10.10"], subnetMasks: ["255.255.255.0"])
        // For bypass mode, we exclude all routes from the VPN to let them go through the default interface
        // This allows all traffic to bypass the VPN and continue using the regular connection
        ipv4Settings.includedRoutes = []  // Empty included routes means nothing goes through VPN
        ipv4Settings.excludedRoutes = []  // Empty excluded routes means no exceptions
        tunnelNetworkSettings.ipv4Settings = ipv4Settings
        
        // Configure DNS settings to use system defaults (bypass mode)
        tunnelNetworkSettings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        
        setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                NSLog("Error setting tunnel network settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            
            // For bypass mode, we don't need to process packets
            // Just call completion handler immediately
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Properly clean up and handle tunnel disconnection
        NSLog("Stopping tunnel with reason: \(reason)")
        
        // Clean up Go library instance
        omOpenmeshAppLib = nil
        
        // Call completion handler to properly signal tunnel shutdown
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