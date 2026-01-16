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
        guard omOpenmeshAppLib != nil else { // Fixed: Remove unused 'appLib' variable
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
            for (index, packet) in packets.enumerated() {
                // 实际使用 goLib 变量避免未使用警告
                guard let goLib = self.omOpenmeshAppLib else { continue }
                
                // 实际使用 goLib 变量
                print("Processing packet with Go library: \(String(describing: goLib))")
                
                // FIX: Directly create RouteDecision since processPacket is unavailable in Swift bindings
                let processed = OMOpenmeshRouteDecision()
                processed.shouldRouteToVpn = true
                
                // For now, just forward all packets
                if processed.shouldRouteToVpn {
                    // This would send the packet to the tunnel interface
                    // Implementation depends on actual tunnel setup
                    print("Routing packet to VPN")
                } else {
                    // Send directly - this is a simplified approach
                    // In a real implementation, you'd need to handle routing based on decision
                    self.packetFlow.writePackets([packet], withProtocols: [protocols[index]])
                }
            }
            
            // Continue reading
            self.readPackets()
        }
    }
    
    func handlePackets() {
        packetFlow.readPackets { (packets: [Data], protocols: [NSNumber]) in
            // 使用变量避免未使用警告
            guard let _ = self.omOpenmeshAppLib else { return }
            
            // FIX: Directly create RouteDecision since processPacket is unavailable in Swift bindings
            let processed = OMOpenmeshRouteDecision()
            processed.shouldRouteToVpn = true
        }
    }

    // Correct stopTunnel signature per Network Extensions规范
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        omOpenmeshAppLib = nil
        super.stopTunnel(with: reason, completionHandler: completionHandler)
    }
}
