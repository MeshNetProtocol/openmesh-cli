//
//  SettingsView.swift
//  MeshFluxIos
//
//  与 MeshFluxMac 设置页对齐：Packet Tunnel（本地网络）、About。
//  切换本地网络时若 VPN 已连接会先断开再重连以应用设置，期间显示 loading 并屏蔽操作。
//

import SwiftUI
import NetworkExtension
import VPNLibrary

struct SettingsView: View {
    @State private var excludeLocalNetworks = true
    @State private var isLoading = true
    @State private var isApplyingSettings = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        Toggle("本地网络不走 VPN", isOn: $excludeLocalNetworks)
                            .disabled(isApplyingSettings)
                            .onChange(of: excludeLocalNetworks) { newValue in
                                Task { await SharedPreferences.excludeLocalNetworks.set(newValue) }
                                applySettingsIfConnected()
                            }
                    } header: {
                        Label("Packet Tunnel", systemImage: "aspectratio.fill")
                    } footer: {
                        Text("当前仅使用 Profile 规则分流。开启「本地网络不走 VPN」后，局域网设备（如打印机、NAS、投屏）直连。切换该选项时若 VPN 已连接将自动重连以应用设置。")
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
                .modifier(FormGroupedStyle())
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
    }

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
        Task { @MainActor in
            let (manager, wasConnected) = await currentVPNManagerAndStatus()
            guard let manager, wasConnected else {
                return
            }
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
                if status == .connected {
                    break
                }
                if status == .invalid || status == .disconnected {
                    break
                }
            }
            isApplyingSettings = false
        }
    }

    private func currentVPNManagerAndStatus() async -> (NETunnelProviderManager?, Bool) {
        await withCheckedContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let manager = managers?.first { $0.localizedDescription == "MeshFlux VPN" }
                let wasConnected = (manager?.connection.status == .connected)
                continuation.resume(returning: (manager, wasConnected))
            }
        }
    }

    private func loadSettings() async {
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        await MainActor.run {
            excludeLocalNetworks = excludeLocal
            isLoading = false
        }
    }
}

/// 仅在 iOS 16+ 应用 .formStyle(.grouped)，以兼容 iOS 15.6。
private struct FormGroupedStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}
