import SwiftUI
@preconcurrency import NetworkExtension
import VPNLibrary

// MARK: - Status from NEVPNStatus (SFI/sing-box style: notification-driven, no polling)
private func vpnStatusText(_ status: NEVPNStatus?) -> String {
    guard let s = status else { return "Disconnected" }
    switch s {
    case .connected: return "Connected"
    case .connecting, .reasserting: return "Connecting..."
    default: return "Disconnected"
    }
}

private func isVPNInProgress(_ status: NEVPNStatus?) -> Bool {
    guard let s = status else { return false }
    return s == .connecting || s == .reasserting
}

struct HomeTabView: View {
    @StateObject private var vpnHolder = VPNProfileHolder()
    @State private var isGlobalMode: Bool = false
    @State private var isRoutingModeLoaded: Bool = false
    @State private var isApplyingSettings: Bool = false
    @StateObject private var groupClient = GroupCommandClient()
    @StateObject private var statusClient = StatusCommandClient()
    @StateObject private var connectionClient = ConnectionCommandClient()
    @State private var showConnectionList = false

    private var vpnStatus: String { vpnStatusText(vpnHolder.profile?.status) }
    private var isConnecting: Bool { isVPNInProgress(vpnHolder.profile?.status) }

    var body: some View {
        ScrollView {
            VStack {
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

                VStack(spacing: 20) {
                    Text("Current Status")
                        .font(.headline)
                    Text(vpnStatus)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(12)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(vpnStatusColor))
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    Button(action: toggleVpn) {
                        Text(vpnStatus == "Connected" ? "Disconnect" : "Connect")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(vpnStatus == "Connected" ? Color.red : Color.blue))
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
                        Picker("Routing Mode", selection: $isGlobalMode) {
                            Text("Rule").tag(false)
                            Text("Global").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!isRoutingModeLoaded || isApplyingSettings)
                        Text(isGlobalMode ? "All traffic uses Proxy." : "Match rules uses Proxy; otherwise Direct.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .onChange(of: isGlobalMode) { newValue in
                        Task {
                            await SharedPreferences.includeAllNetworks.set(newValue)
                            await applySettingsIfConnected()
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                .padding(.horizontal)

                if vpnStatus == "Connected" {
                    StatusCardsView(status: statusClient.status)
                        .padding(.horizontal)
                    OutboundGroupSectionView(groupClient: groupClient)
                        .padding(.horizontal)
                    Button {
                        showConnectionList = true
                    } label: {
                        Label("连接", systemImage: "list.bullet.rectangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }

                Spacer(minLength: 24)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isApplyingSettings { applyingSettingsOverlay }
        }
        .sheet(isPresented: $showConnectionList) {
            ConnectionListView(connectionClient: connectionClient)
        }
        .allowsHitTesting(!isApplyingSettings)
        .onAppear {
            Task {
                await vpnHolder.load()
                await loadRoutingMode()
            }
            updateCommandClients(connected: vpnStatus == "Connected")
        }
        .onDisappear {
            statusClient.disconnect()
            groupClient.disconnect()
        }
        .onChange(of: vpnStatus) { newStatus in
            updateCommandClients(connected: newStatus == "Connected")
        }
    }

    private var applyingSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4)
                Text("正在应用设置…")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var vpnStatusColor: Color {
        switch vpnStatus {
        case "Connected": return Color.green
        case "Connecting...": return Color.blue
        default: return Color.gray
        }
    }

    private func updateCommandClients(connected: Bool) {
        if connected {
            statusClient.connect()
            groupClient.connect()
        } else {
            statusClient.disconnect()
            groupClient.disconnect()
        }
    }

    private func loadRoutingMode() async {
        let value = await SharedPreferences.includeAllNetworks.get()
        await MainActor.run {
            isGlobalMode = value
            isRoutingModeLoaded = true
        }
    }

    private func applySettingsIfConnected() async {
        let (manager, wasConnected) = await currentVPNManagerAndStatus()
        guard let manager, wasConnected else { return }
        await MainActor.run { isApplyingSettings = true }
        manager.connection.stopVPNTunnel()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let includeAll = await SharedPreferences.includeAllNetworks.get()
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto.includeAllNetworks = includeAll
            proto.excludeLocalNetworks = excludeLocal
            manager.protocolConfiguration = proto
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                manager.saveToPreferences { _ in cont.resume() }
            }
        }
        let connection = manager.connection
        var oneShotObserver: Any?
        oneShotObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: connection,
            queue: .main
        ) { notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let s = conn.status
            if s == .connected || s == .disconnected || s == .invalid {
                if let o = oneShotObserver {
                    NotificationCenter.default.removeObserver(o)
                }
                oneShotObserver = nil
                isApplyingSettings = false
            }
        }
        do {
            try manager.connection.startVPNTunnel(options: nil)
        } catch {
            if let o = oneShotObserver {
                NotificationCenter.default.removeObserver(o)
            }
            await MainActor.run { isApplyingSettings = false }
        }
        // Timeout: clear overlay after 25s even if no notification (e.g. stuck)
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            await MainActor.run {
                if isApplyingSettings {
                    isApplyingSettings = false
                    if let o = oneShotObserver {
                        NotificationCenter.default.removeObserver(o)
                    }
                }
            }
        }
    }

    private func currentVPNManagerAndStatus() async -> (NETunnelProviderManager?, Bool) {
        await withCheckedContinuation { cont in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let manager = managers?.first { $0.localizedDescription == "MeshFlux VPN" }
                let connected = (manager?.connection.status == .connected)
                cont.resume(returning: (manager, connected))
            }
        }
    }

    private func toggleVpn() {
        Task {
            await doToggleVpn()
        }
    }

    private func doToggleVpn() async {
        if vpnHolder.profile?.status == .connected {
            try? await vpnHolder.profile?.stop()
            return
        }
        // Ensure profile exists (create manager if needed)
        if vpnHolder.profile == nil {
            await ensureMeshFluxManagerExists()
            await vpnHolder.load()
        }
        guard let profile = vpnHolder.profile else {
            return
        }
        do {
            try await profile.start()
        } catch {
            print("Error starting VPN tunnel: \(error)")
        }
    }

    /// Create "MeshFlux VPN" manager if missing; no polling.
    private func ensureMeshFluxManagerExists() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                if managers?.first(where: { $0.localizedDescription == "MeshFlux VPN" }) != nil {
                    cont.resume()
                    return
                }
                let manager = NETunnelProviderManager()
                let includeAll = SharedPreferences.includeAllNetworks.getBlocking()
                let excludeLocal = SharedPreferences.excludeLocalNetworks.getBlocking()
                let proto = NETunnelProviderProtocol()
                proto.serverAddress = "MeshFlux Server"
                proto.providerBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension"
                proto.disconnectOnSleep = false
                proto.includeAllNetworks = includeAll
                proto.excludeLocalNetworks = excludeLocal
                proto.providerConfiguration = [:]
                manager.protocolConfiguration = proto
                manager.localizedDescription = "MeshFlux VPN"
                manager.isEnabled = true
                manager.saveToPreferences { _ in
                    manager.loadFromPreferences { _ in
                        cont.resume()
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
