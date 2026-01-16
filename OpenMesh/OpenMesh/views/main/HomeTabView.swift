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
                if status.connected {
                    self.vpnStatus = "Connected"
                } else {
                    self.vpnStatus = "Disconnected"
                }
            }
        }
    }
    
    private func toggleVpn() {
        guard let appLib = appLib else { return }
        
        isConnecting = true
        
        DispatchQueue.global(qos: .background).async {
            do {
                if self.vpnStatus == "Connected" {
                    // Disconnect VPN
                    try NEPacketTunnelProviderManager.shared().loadFromPreferences { error in
                        if let error = error {
                            print("Error loading preferences: \(error)")
                            return
                        }
                        
                        NEPacketTunnelProviderManager.shared().providerBundleIdentifier = "com.openmesh.vpn"
                        NEPacketTunnelProviderManager.shared().isEnabled = false
                        NEPacketTunnelProviderManager.shared().saveToPreferences { error in
                            if let error = error {
                                print("Error saving preferences: \(error)")
                            }
                            DispatchQueue.main.async {
                                self.vpnStatus = "Disconnected"
                                self.isConnecting = false
                            }
                        }
                    }
                } else {
                    // Connect VPN
                    let manager = NEPacketTunnelProviderManager()
                    manager.loadFromPreferences { error in
                        if let error = error {
                            print("Error loading preferences: \(error)")
                            DispatchQueue.main.async {
                                self.isConnecting = false
                            }
                            return
                        }
                        
                        let providerProtocol = NEPacketTunnelProviderProtocol(dictionary: [:])
                        providerProtocol.serverAddress = "127.0.0.1"
                        
                        manager.protocolConfiguration = providerProtocol
                        manager.onDemandRules = []
                        manager.onDemandEnabled = false
                        manager.localizedDescription = "OpenMesh VPN"
                        manager.isEnabled = true
                        
                        manager.saveToPreferences { error in
                            if let error = error {
                                print("Error saving preferences: \(error)")
                                DispatchQueue.main.async {
                                    self.isConnecting = false
                                }
                                return
                            }
                            
                            manager.loadFromPreferences { error in
                                if let error = error {
                                    print("Error loading preferences after save: \(error)")
                                    DispatchQueue.main.async {
                                        self.isConnecting = false
                                    }
                                    return
                                }
                                
                                manager.connect()
                                DispatchQueue.main.async {
                                    self.vpnStatus = "Connecting..."
                                }
                                
                                // Check connection status periodically
                                let statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                                    self.updateVpnStatus()
                                    if self.vpnStatus == "Connected" {
                                        timer.invalidate()
                                        DispatchQueue.main.async {
                                            self.isConnecting = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Error toggling VPN: \(error)")
                DispatchQueue.main.async {
                    self.isConnecting = false
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