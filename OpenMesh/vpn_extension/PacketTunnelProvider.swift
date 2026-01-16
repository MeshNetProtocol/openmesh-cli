//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/16.
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
        
        // Correct NETunnelNetworkSettings initialization with tunnel remote address
        let settings = NETunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
        
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Start reading packets
            self.readPackets()
            completionHandler(nil)
        }
    }
    
    private func readPackets() {
        packetFlow.readPackets { (packets: [Data], protocols: [NSNumber]) in
            // Correct closure parameters per Swift type safety规范
            guard !packets.isEmpty else {
                self.readPackets()
                return
            }
            
            // Process each packet through the Go library
            // Variables kept for future implementation when Go logic is active
            let packetsToForward: [Data] = []
            _ = [NSNumber]() // 替换 protocolsForForwardedPackets
            
            for (index, packet) in packets.enumerated() {
                // 保留对 Go 库的引用，用于未来功能扩展
                _ = self.omOpenmeshAppLib
                
                // For now, simulate the Go code decision: all packets bypass VPN
                // This replicates the intended behavior of the Go function
                // 在未来，这里将调用 Go 函数进行实际决策
                _ = false // 原来的 shouldRouteToVpn 变量
                
                // Currently, all packets are sent directly through the interface
                // This simulates sending directly through the network interface without VPN processing
                self.packetFlow.writePackets([packet], withProtocols: [protocols[index]])
            }
            
            // If there are packets that should be forwarded through VPN, handle them
            // This is where you would implement the actual VPN tunneling logic
            if !packetsToForward.isEmpty {
                // In a real implementation, these packets would be sent through the VPN tunnel
                print("Packets to be forwarded through VPN: \(packetsToForward.count)")
            }
            
            // Continue reading
            self.readPackets()
        }
    }
}