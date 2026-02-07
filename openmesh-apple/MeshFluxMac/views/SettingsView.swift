//
//  SettingsView.swift
//  MeshFluxMac
//
//  商用/用户友好：设置单页展示 App、Packet Tunnel、About，无二级菜单；无 Debug。
//  切换「本地网络不走 VPN」时若 VPN 已连接会先断开再重连以应用设置，期间显示 loading 并屏蔽操作。
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

    @State private var isLoading = true
    @State private var unmatchedTrafficOutbound = "direct"

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
                        Text("本地网络不走 VPN：默认开启（不可在此关闭）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("未命中流量出口", selection: $unmatchedTrafficOutbound) {
                            Text("Proxy").tag("proxy")
                            Text("Direct").tag("direct")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: unmatchedTrafficOutbound) { newValue in
                            Task { await vpnController.setUnmatchedTrafficOutbound(newValue) }
                        }
                    } header: {
                        Label("Packet Tunnel", systemImage: "aspectratio.fill")
                    } footer: {
                        Text("命中 geoip/geosite 仍走直连；命中 force_proxy 仍走代理。这个开关只影响剩余未命中流量。")
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
        .onAppear { Task { await loadSettings() } }
        .alert("App", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func loadSettings() async {
        #if os(macOS)
        let start = SMAppService.mainApp.status == .enabled
        await MainActor.run { startAtLogin = start }
        #endif
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        let unmatched = await SharedPreferences.unmatchedTrafficOutbound.get()
        if excludeLocal == false {
            await SharedPreferences.excludeLocalNetworks.set(true)
            if vpnController.isConnected {
                await vpnController.reconnectToApplySettings()
            }
        }
        await MainActor.run {
            unmatchedTrafficOutbound = (unmatched == "direct") ? "direct" : "proxy"
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
