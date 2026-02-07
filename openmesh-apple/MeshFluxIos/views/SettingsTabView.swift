//
//  SettingsTabView.swift
//  MeshFluxIos
//
//  与 Mac 设置对齐：应用与版本、VPN 开关、流量商户选择、About。
//  切换流量商户时若 VPN 已连接会先断开再重连，期间显示 loading。
//

import SwiftUI
import NetworkExtension
import VPNLibrary

struct SettingsTabView: View {
    @EnvironmentObject private var vpnController: VPNController
    @State private var appVersion: String = "—"
    @State private var unmatchedTrafficOutbound = "direct"
    @State private var isLoading = true
    @State private var isApplyingSettings = false
    @State private var settingsTask: Task<Void, Never>?

    private var vpnStatusText: String {
        switch vpnController.status {
        case .connected: return "Connected"
        case .connecting, .reasserting: return "Connecting..."
        default: return "Disconnected"
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    sectionAppVersion
                    sectionVPN
                    sectionRouting
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
            settingsTask?.cancel()
            settingsTask = Task {
                await loadAll()
                await MainActor.run { isLoading = false }
            }
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
                Text(vpnStatusText)
                    .foregroundStyle(vpnStatusColor(vpnStatusText))
                Spacer()
                Button(vpnController.isConnected ? "断开" : "连接") {
                    vpnController.toggleVPN()
                }
                .disabled(vpnController.isConnecting)
            }
            if vpnController.isConnecting {
                ProgressView()
                    .scaleEffect(0.9)
            }
        } header: {
            Label("VPN", systemImage: "network")
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

    private var sectionRouting: some View {
        Section {
            Picker("未命中流量出口", selection: $unmatchedTrafficOutbound) {
                Text("Direct").tag("direct")
                Text("Proxy").tag("proxy")
            }
            .pickerStyle(.segmented)
            .onChange(of: unmatchedTrafficOutbound) { value in
                Task {
                    await SharedPreferences.unmatchedTrafficOutbound.set(value)
                    await applySettingsIfConnected()
                }
            }
        } header: {
            Label("路由策略", systemImage: "arrow.triangle.branch")
        } footer: {
            Text("命中 geoip/geosite 仍走直连；命中 force_proxy 仍走代理。该选项只影响未命中流量。")
        }
    }

    private func vpnStatusColor(_ vpnStatus: String) -> Color {
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
        await enforceExcludeLocalNetworks()
        await loadRoutingPreference()
    }

    private func loadRoutingPreference() async {
        let value = await SharedPreferences.unmatchedTrafficOutbound.get()
        await MainActor.run {
            unmatchedTrafficOutbound = (value == "proxy") ? "proxy" : "direct"
        }
    }

    private func loadVersion() async {
        let version: String
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        version = build.isEmpty ? short : "\(short) (\(build))"
        await MainActor.run { appVersion = version.isEmpty ? "—" : version }
    }

    private func enforceExcludeLocalNetworks() async {
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        if excludeLocal == false {
            await SharedPreferences.excludeLocalNetworks.set(true)
            if vpnController.isConnected {
                await applySettingsIfConnected()
            }
        }
    }

    private func applySettingsIfConnected() async {
        guard vpnController.isConnected else { return }
        await MainActor.run { isApplyingSettings = true }
        defer { Task { @MainActor in isApplyingSettings = false } }

        // For iOS: simplest and most reliable is stop → wait → start, letting ExtensionProfile.start()
        // re-apply current SharedPreferences to protocolConfiguration.
        await vpnController.reconnectToApplySettings()
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
