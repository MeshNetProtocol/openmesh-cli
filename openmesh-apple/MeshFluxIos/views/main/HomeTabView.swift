import SwiftUI
import NetworkExtension

struct HomeTabView: View {
    @State private var vpnStatus: String = "Disconnected"
    @State private var isConnecting: Bool = false
    @State private var routingMode: RoutingMode
    
    init() {
        _routingMode = State(initialValue: RoutingModeStore.read())
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
                    
                Text("MeshFlux")
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Routing Mode")
                        .font(.headline)

                    Picker("Routing Mode", selection: $routingMode) {
                        Text("Rule").tag(RoutingMode.rule)
                        Text("Global").tag(RoutingMode.global)
                    }
                    .pickerStyle(.segmented)

                    Text(routingMode == .global ? "All traffic uses Proxy." : "Match rules uses Proxy; otherwise Direct.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .onChange(of: routingMode) { newValue in
                    RoutingModeStore.write(newValue)
                }
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
        Task {
            let status = await GoEngine.shared.getVpnStatus()
            await MainActor.run {
                if let status = status, status.connected {
                    self.vpnStatus = "Connected"
                } else {
                    self.vpnStatus = "Disconnected"
                }
            }
        }
    }
    
    private func toggleVpn() {
        isConnecting = true
        
        DispatchQueue.global(qos: .background).async {
            if self.vpnStatus == "Connected" {
                // Disconnect VPN
                NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
                    if let error = error {
                        print("Error loading VPN configurations: \(error)")
                        DispatchQueue.main.async {
                            self.isConnecting = false
                        }
                        return
                    }
                    
                    if let manager = managers?.first(where: { $0.localizedDescription == "MeshFlux VPN" }) {
                        manager.connection.stopVPNTunnel()
                        
                        // Update UI immediately but also check for actual disconnection
                        DispatchQueue.main.async {
                            self.vpnStatus = "Disconnected"
                            self.isConnecting = false
                        }
                        
                        // Wait briefly and then recheck actual status to confirm disconnection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.updateVpnStatus()
                        }
                    } else {
                        // If no manager found, just update UI
                        DispatchQueue.main.async {
                            self.vpnStatus = "Disconnected"
                            self.isConnecting = false
                        }
                    }
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
                    if let existingManager = managers?.first(where: { $0.localizedDescription == "MeshFlux VPN" }) {
                        // Use existing manager if found
                        manager = existingManager
                    } else {
                        // Create new manager if none exists
                        manager = NETunnelProviderManager()
                    }
                    
                    // Configure tunnel protocol - Use NETunnelProviderProtocol for Packet Tunnel
                    let protocolConfig = NETunnelProviderProtocol()
                    protocolConfig.serverAddress = "MeshFlux Server"
                    protocolConfig.providerBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension" // Use the correct bundle ID
                    protocolConfig.disconnectOnSleep = false
                    
                    // Don't set authenticationMethod which causes "Unsupported authenticationMethod" error
                    // Just configure the necessary tunnel parameters
                    
                    // Tunnel provider configuration
                    protocolConfig.providerConfiguration = [:]
                    
                    // Set the protocol configuration
                    manager.protocolConfiguration = protocolConfig
                    manager.localizedDescription = "MeshFlux VPN"
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
