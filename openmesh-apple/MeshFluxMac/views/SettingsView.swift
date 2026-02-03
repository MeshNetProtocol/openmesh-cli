//
//  SettingsView.swift
//  MeshFluxMac
//
//  商用/用户友好：设置单页展示 App、Packet Tunnel、About，无二级菜单；无 Debug。
//  切换「模式」或「本地网络」时若 VPN 已连接会先断开再重连以应用设置，期间显示 loading 并屏蔽操作。
//

import SwiftUI
import VPNLibrary
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @ObservedObject var vpnController: VPNController

    // App
    @State private var startAtLogin = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    // Packet Tunnel
    @State private var isGlobalMode = false
    @State private var excludeLocalNetworks = true

    @State private var isLoading = true
    @State private var isApplyingSettings = false

    init(vpnController: VPNController) {
        self.vpnController = vpnController
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    #if os(macOS)
                    Section {
                        Toggle("Start At Login", isOn: $startAtLogin)
                            .onChange(of: startAtLogin) { newValue in
                                updateLoginItems(newValue)
                            }
                    } header: {
                        Label("App", systemImage: "app.badge.fill")
                    } footer: {
                        Text("Launch the application when the system is logged in. If enabled at the same time as Show in Menu Bar and Keep Menu Bar in Background, the application interface will not be opened automatically.")
                    }
                    #endif

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
                        Text("按规则分流：仅匹配规则的流量走 VPN；全局：除排除项外全部走 VPN。开启「本地网络不走 VPN」后，局域网设备（如打印机、NAS、投屏）直连。切换模式或本地网络时若 VPN 已连接将自动重连以应用设置。")
                    }

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
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("设置")
        .overlay {
            if isApplyingSettings {
                applyingSettingsOverlay
            }
        }
        .allowsHitTesting(!isApplyingSettings)
        .onAppear { Task { await loadSettings() } }
        .alert("App", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// 全屏 loading：切换模式/本地网络时断开并重连 VPN 期间展示，阻止与整页 UI 的交互。
    private var applyingSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("正在应用设置…")
                    .font(.headline)
                Text("断开并重连 VPN 中，请勿切换其他选项")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applySettingsIfConnected() {
        guard vpnController.isConnected else { return }
        Task { @MainActor in
            isApplyingSettings = true
            await vpnController.reconnectToApplySettings()
            let deadline = Date().addingTimeInterval(30)
            while vpnController.isConnecting && Date() < deadline {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            isApplyingSettings = false
        }
    }

    private func loadSettings() async {
        #if os(macOS)
        let start = SMAppService.mainApp.status == .enabled
        await MainActor.run { startAtLogin = start }
        #endif
        let includeAllNetworks = await SharedPreferences.includeAllNetworks.get()
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        await MainActor.run {
            isGlobalMode = includeAllNetworks
            excludeLocalNetworks = excludeLocal
            isLoading = false
        }
    }

    #if os(macOS)
    private func updateLoginItems(_ startAtLogin: Bool) {
        do {
            if startAtLogin {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    #endif
}
