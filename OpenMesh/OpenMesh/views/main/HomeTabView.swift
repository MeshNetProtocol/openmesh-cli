import SwiftUI
import NetworkExtension
import OpenMeshGo

struct HomeTabView: View {
    @State private var vpnStatus: String = "Disconnected"
    @State private var isConnecting: Bool = false
    
    private var appLib: OMOpenmeshAppLib?
    
    init() {
        appLib = OMOpenmeshNewLib()
        updateVpnStatus()
    }
    
    var body: some View {
        VStack {
            // Logo and app name
            VStack(spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding()
                    
                Text("OpenMesh")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)
            
            // VPN Status section
            VStack(spacing: 20) {
                Text("Current Status")
                    .font(.headline)
                    
                Text(vpnStatus)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(12)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(vpnStatusColor)
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    
                Button(action: toggleVpn) {
                    Text(vpnStatus == "Connected" ? "Disconnect" : "Connect")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(vpnStatus == "Connected" ? Color.red : Color.blue)
                        )
                }
                .disabled(isConnecting)
                .opacity(isConnecting ? 0.5 : 1.0)
                
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                
                Text("All traffic will be routed through the MeshNet Protocol")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var vpnStatusColor: Color {
        switch vpnStatus {
        case "Connected":
            return Color.green
        case "Connecting...":
            return Color.blue
        default:
            return Color.gray
        }
    }
    
    private func updateVpnStatus() {
        DispatchQueue.global(qos: .background).async {
            guard let appLib = self.appLib else { return }
            
            let status = appLib.getVpnStatus()
            DispatchQueue.main.async {
                if let status = status, status.connected {  // 解包可选类型
                    self.vpnStatus = "Connected"
                } else {
                    self.vpnStatus = "Disconnected"
                }
            }
        }
    }
    
    private func toggleVpn() {
        // 使用占位符 _ 忽略 appLib 的值，因为现在我们只需要检查它是否为 nil
        guard let _ = appLib else { return }
        
        isConnecting = true
        
        DispatchQueue.global(qos: .background).async {
            if self.vpnStatus == "Connected" {
                // Disconnect VPN
                NEVPNManager.shared().connection.stopVPNTunnel()
                
                DispatchQueue.main.async {
                    self.vpnStatus = "Disconnected"
                    self.isConnecting = false
                }
            } else {
                // Load existing VPN configuration or create a new one
                NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
                    if let error = error {
                        print("Error loading existing VPN configurations: \(error)")
                        DispatchQueue.main.async {
                            self.isConnecting = false
                        }
                        return
                    }
                    
                    // Get or create VPN manager
                    let manager: NETunnelProviderManager
                    if let existingManager = managers?.first(where: { $0.localizedDescription == "OpenMesh VPN" }) {
                        // Use existing manager if found
                        manager = existingManager
                    } else {
                        // Create new manager if none exists
                        manager = NETunnelProviderManager()
                    }
                    
                    // Configure tunnel protocol - Use NETunnelProviderProtocol for Packet Tunnel
                    let protocolConfig = NETunnelProviderProtocol()
                    protocolConfig.serverAddress = "OpenMesh Server"
                    protocolConfig.providerBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension" // Use the correct bundle ID
                    protocolConfig.disconnectOnSleep = false
                    
                    // Don't set authenticationMethod which causes "Unsupported authenticationMethod" error
                    // Just configure the necessary tunnel parameters
                    
                    // Tunnel provider configuration
                    protocolConfig.providerConfiguration = [:]
                    
                    // Set the protocol configuration
                    manager.protocolConfiguration = protocolConfig
                    manager.localizedDescription = "OpenMesh VPN"
                    manager.isEnabled = true
                    
                    // Save to system preferences
                    manager.saveToPreferences { saveError in
                        if let saveError = saveError {
                            print("Error saving VPN preferences: \(saveError)")
                            DispatchQueue.main.async {
                                self.isConnecting = false
                            }
                            return
                        }
                        
                        print("VPN configuration saved successfully")
                        
                        // Reload the configuration to ensure it's properly loaded
                        manager.loadFromPreferences { reloadError in
                            if let reloadError = reloadError {
                                print("Error reloading VPN preferences: \(reloadError)")
                                DispatchQueue.main.async {
                                    self.isConnecting = false
                                }
                                return
                            }
                            
                            DispatchQueue.main.async {
                                // Start VPN connection
                                do {
                                    try manager.connection.startVPNTunnel(options: nil)
                                    
                                    self.vpnStatus = "Connecting..."
                                    
                                    // Check connection status periodically
                                    _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                                        self.updateVpnStatus()
                                        if self.vpnStatus == "Connected" || self.vpnStatus != "Connecting..." {
                                            timer.invalidate()
                                            DispatchQueue.main.async {
                                                self.isConnecting = false
                                            }
                                        }
                                    }
                                } catch {
                                    print("Error starting VPN tunnel: \(error)")
                                    DispatchQueue.main.async {
                                        self.isConnecting = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HomeTabView_Previews: PreviewProvider {
    static var previews: some View {
        HomeTabView()
    }
}