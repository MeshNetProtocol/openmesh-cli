//
//  SettingsTabView.swift
//  MeshFluxIos
//
//  与 Mac 设置对齐：应用与版本、VPN 开关、配置选择、Packet Tunnel（模式、本地网络）、About。
//  切换模式/本地网络/配置时若 VPN 已连接会先断开再重连，期间显示 loading。
//

import SwiftUI
import NetworkExtension
import VPNLibrary
import OpenMeshGo

struct SettingsTabView: View {
    @State private var appVersion: String = "—"
    @State private var vpnStatus: String = "Disconnected"
    @State private var isConnecting = false
    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var isGlobalMode = false
    @State private var excludeLocalNetworks = true
    @State private var isLoading = true
    @State private var isApplyingSettings = false
    @State private var profileLoadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    sectionAppVersion
                    sectionVPN
                    sectionProfile
                    sectionPacketTunnel
                    sectionAbout
                }
                .modifier(SettingsFormGroupedStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("设置")
        .overlay {
            if isApplyingSettings { applyingSettingsOverlay }
        }
        .allowsHitTesting(!isApplyingSettings)
        .onAppear {
            Task { await loadAll() }
        }
    }

    private var sectionAppVersion: some View {
        Section {
            HStack {
                Text("MeshFlux")
                    .font(.headline)
                Spacer()
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("应用与版本", systemImage: "info.circle")
        }
    }

    private var sectionVPN: some View {
        Section {
            HStack {
                Text(vpnStatus)
                    .foregroundStyle(vpnStatusColor)
                Spacer()
                Button(vpnStatus == "Connected" ? "断开" : "连接") {
                    toggleVpn()
                }
                .disabled(isConnecting)
            }
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.9)
            }
        } header: {
            Label("VPN", systemImage: "network")
        }
    }

    private var sectionProfile: some View {
        Section {
            if let err = profileLoadError {
                Text("加载配置失败：\(err)")
                    .foregroundStyle(.secondary)
            } else if profileList.isEmpty {
                Text("暂无配置")
                    .foregroundStyle(.secondary)
            } else {
                Picker("配置", selection: $selectedProfileID) {
                    ForEach(profileList, id: \.mustID) { p in
                        Text(p.name).tag(p.mustID)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isApplyingSettings)
                .onChange(of: selectedProfileID) { newId in
                    Task { await switchProfile(newId) }
                }
            }
        } header: {
            Label("配置", systemImage: "list.bullet")
        } footer: {
            Text("切换配置后若 VPN 已连接将自动重连以应用新配置。")
        }
    }

    private var sectionPacketTunnel: some View {
        Section {
            Picker("模式", selection: $isGlobalMode) {
                Text("按规则分流").tag(false)
                Text("全局").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(isApplyingSettings)
            .onChange(of: isGlobalMode) { newValue in
                Task { await SharedPreferences.includeAllNetworks.set(newValue) }
                applySettingsIfConnected()
            }

            Toggle("本地网络不走 VPN", isOn: $excludeLocalNetworks)
                .disabled(isApplyingSettings)
                .onChange(of: excludeLocalNetworks) { newValue in
                    Task { await SharedPreferences.excludeLocalNetworks.set(newValue) }
                    applySettingsIfConnected()
                }
        } header: {
            Label("Packet Tunnel", systemImage: "aspectratio.fill")
        } footer: {
            Text("按规则分流：仅匹配规则的流量走 VPN；全局：除排除项外全部走 VPN。开启「本地网络不走 VPN」后，局域网设备直连。")
        }
    }

    private var sectionAbout: some View {
        Section("About") {
            Link(destination: URL(string: "https://meshnetprotocol.github.io/")!) {
                Label("Documentation", systemImage: "doc.on.doc.fill")
            }
            .foregroundStyle(Color.accentColor)
            Link(destination: URL(string: "https://github.com/MeshNetProtocol/openmesh-cli")!) {
                Label("Source Code", systemImage: "pills.fill")
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    private var vpnStatusColor: Color {
        switch vpnStatus {
        case "Connected": return .green
        case "Connecting...": return .blue
        default: return .secondary
        }
    }

    private var applyingSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4)
                Text("正在应用设置…").font(.headline)
                Text("断开并重连 VPN 中，请勿切换其他选项")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadAll() async {
        await loadVersion()
        await loadVPNStatus()
        await loadProfiles()
        await loadPacketTunnelSettings()
        await MainActor.run { isLoading = false }
    }

    private func loadVersion() async {
        let version: String
        let libbox = OMLibboxVersion()
        if !libbox.isEmpty, libbox.lowercased() != "unknown" {
            version = libbox
        } else {
            let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            version = build.isEmpty ? short : "\(short) (\(build))"
        }
        await MainActor.run { appVersion = version.isEmpty ? "—" : version }
    }

    private func loadVPNStatus() async {
        let (_, connected) = await currentVPNManagerAndStatus()
        await MainActor.run {
            vpnStatus = connected ? "Connected" : "Disconnected"
        }
    }

    private func loadProfiles() async {
        profileLoadError = nil
        do {
            let list = try await ProfileManager.list()
            var sid = await SharedPreferences.selectedProfileID.get()
            if list.isEmpty {
                await MainActor.run {
                    profileList = []
                    selectedProfileID = -1
                }
                return
            }
            if list.first(where: { $0.mustID == sid }) == nil {
                sid = list[0].mustID
                await SharedPreferences.selectedProfileID.set(sid)
            }
            await MainActor.run {
                profileList = list
                selectedProfileID = sid
            }
        } catch {
            await MainActor.run {
                profileLoadError = error.localizedDescription
                profileList = []
            }
        }
    }

    private func loadPacketTunnelSettings() async {
        let includeAll = await SharedPreferences.includeAllNetworks.get()
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        await MainActor.run {
            isGlobalMode = includeAll
            excludeLocalNetworks = excludeLocal
        }
    }

    private func switchProfile(_ newId: Int64) async {
        await SharedPreferences.selectedProfileID.set(newId)
        applySettingsIfConnected()
    }

    private func toggleVpn() {
        let currentlyConnected = (vpnStatus == "Connected")
        isConnecting = true
        loadAllVPN { manager in
            guard let manager else {
                DispatchQueue.main.async { isConnecting = false }
                return
            }
            if currentlyConnected {
                manager.connection.stopVPNTunnel()
                DispatchQueue.main.async {
                    vpnStatus = "Disconnected"
                    isConnecting = false
                }
            } else {
                do {
                    try manager.connection.startVPNTunnel(options: nil)
                    DispatchQueue.main.async { vpnStatus = "Connecting..." }
                    self.pollVPNStatus(manager: manager)
                } catch {
                    DispatchQueue.main.async { isConnecting = false }
                }
            }
        }
    }

    private func loadAllVPN(completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let manager = managers?.first { $0.localizedDescription == "MeshFlux VPN" }
            if manager == nil {
                let newManager = NETunnelProviderManager()
                let proto = NETunnelProviderProtocol()
                proto.serverAddress = "MeshFlux Server"
                proto.providerBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension"
                proto.providerConfiguration = [:]
                newManager.protocolConfiguration = proto
                newManager.localizedDescription = "MeshFlux VPN"
                newManager.isEnabled = true
                newManager.saveToPreferences { _ in
                    newManager.loadFromPreferences { _ in
                        completion(newManager)
                    }
                }
            } else {
                completion(manager)
            }
        }
    }

    private func pollVPNStatus(manager: NETunnelProviderManager) {
        func check() {
            switch manager.connection.status {
            case .connected:
                DispatchQueue.main.async { vpnStatus = "Connected"; isConnecting = false }
            case .invalid, .disconnected:
                DispatchQueue.main.async { isConnecting = false }
            default:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: check)
    }

    private func applySettingsIfConnected() {
        Task { @MainActor in
            let (manager, wasConnected) = await currentVPNManagerAndStatus()
            guard let manager, wasConnected else { return }
            isApplyingSettings = true
            manager.connection.stopVPNTunnel()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                try manager.connection.startVPNTunnel(options: nil)
            } catch {
                isApplyingSettings = false
                return
            }
            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = manager.connection.status
                if status == .connected { break }
                if status == .invalid || status == .disconnected { break }
            }
            isApplyingSettings = false
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
}

private struct SettingsFormGroupedStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}
