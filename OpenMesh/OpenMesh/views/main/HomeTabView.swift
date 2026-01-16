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
                // Connect VPN - 创建新的 VPN 配置
                let manager = NEVPNManager.shared()
                manager.loadFromPreferences { error in
                    if let error = error {
                        print("Error loading preferences: \(error)")
                        DispatchQueue.main.async {
                            self.isConnecting = false
                        }
                        return
                    }
                    
                    // 配置IKEv2协议
                    let protocolConfig = NEVPNProtocolIKEv2()
                    protocolConfig.serverAddress = "127.0.0.1"
                    protocolConfig.username = "openmesh"
                    protocolConfig.passwordReference = nil // 通过App的凭证存储来设置
                    protocolConfig.disconnectOnSleep = false
                    
                    manager.protocolConfiguration = protocolConfig
                    manager.localizedDescription = "OpenMesh VPN"
                    manager.isEnabled = true
                    
                    // saveToPreferences() 不抛出异常，所以不需要 do-catch 块
                    manager.saveToPreferences { error in
                        if let error = error {
                            print("Error saving VPN preferences: \(error)")
                            DispatchQueue.main.async {
                                self.isConnecting = false
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            // startVPNTunnel 方法会抛出异常，需要使用 try
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

struct HomeTabView_Previews: PreviewProvider {
    static var previews: some View {
        HomeTabView()
    }
}