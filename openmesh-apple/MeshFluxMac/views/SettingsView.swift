//
//  SettingsView.swift
//  MeshFluxMac
//
//  与 sing-box SettingView 对齐：多 Tab（App / Core / Packet Tunnel / On Demand Rules / Profile Override / About / Debug）。
//  商业化版本隐藏日志与 Debug 入口（AppConfig.showLogsInUI = false）。
//

import SwiftUI
import VPNLibrary

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AppSettingsView()
                } label: {
                    Label("App", systemImage: "app.badge.fill")
                }
                NavigationLink {
                    CoreSettingsView()
                } label: {
                    Label("Core", systemImage: "shippingbox.fill")
                }
                NavigationLink {
                    PacketTunnelSettingsView()
                } label: {
                    Label("Packet Tunnel", systemImage: "aspectratio.fill")
                }
                NavigationLink {
                    OnDemandRulesSettingsView()
                } label: {
                    Label("On Demand Rules", systemImage: "filemenu.and.selection")
                }
                NavigationLink {
                    ProfileOverrideSettingsView()
                } label: {
                    Label("Profile Override", systemImage: "square.dashed.inset.filled")
                }
            }
            Section("About") {
                Link(destination: URL(string: "https://github.com/MeshNetProtocol/openmesh-cli")!) {
                    Label("Source Code", systemImage: "pills.fill")
                }
                .foregroundStyle(Color.accentColor)
            }
            if AppConfig.showLogsInUI {
                Section("Debug") {
                    NavigationLink {
                        ServiceLogSettingsView()
                    } label: {
                        Label("Service Log", systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("设置")
    }
}

// MARK: - App（VPN + 菜单栏等，与 sing-box MacAppView 对应）
private struct AppSettingsView: View {
    @State private var alwaysOn = false
    @State private var includeAllNetworks = false
    @State private var maxLogLines = 300
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
            Section("VPN") {
                Toggle("始终开启 (Always On)", isOn: $alwaysOn)
                    .onChange(of: alwaysOn) { newValue in
                        Task { await SharedPreferences.alwaysOn.set(newValue) }
                    }
                Toggle("包含所有网络 (Include All Networks)", isOn: $includeAllNetworks)
                    .onChange(of: includeAllNetworks) { newValue in
                        Task { await SharedPreferences.includeAllNetworks.set(newValue) }
                    }
            }
            if AppConfig.showLogsInUI {
                Section("日志") {
                    HStack {
                        Text("最大日志行数")
                        TextField("", value: $maxLogLines, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: maxLogLines) { newValue in
                                let clamped = min(10000, max(100, newValue))
                                if clamped != newValue { maxLogLines = clamped }
                                Task { await SharedPreferences.maxLogLines.set(clamped) }
                            }
                    }
                }
            }
        }
        }
        }
        .formStyle(.grouped)
        .navigationTitle("App")
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        Task {
            let on = await SharedPreferences.alwaysOn.get()
            let include = await SharedPreferences.includeAllNetworks.get()
            let lines = await SharedPreferences.maxLogLines.get()
            await MainActor.run {
                alwaysOn = on
                includeAllNetworks = include
                maxLogLines = lines
                isLoading = false
            }
        }
    }
}

// MARK: - Core（占位，与 sing-box CoreView 对应）
private struct CoreSettingsView: View {
    var body: some View {
        Form {
            Text("Core 设置占位，后续对齐 sing-box CoreView。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Core")
    }
}

// MARK: - Packet Tunnel（占位）
private struct PacketTunnelSettingsView: View {
    var body: some View {
        Form {
            Text("Packet Tunnel 设置占位。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Packet Tunnel")
    }
}

// MARK: - On Demand Rules（占位）
private struct OnDemandRulesSettingsView: View {
    var body: some View {
        Form {
            Text("On Demand Rules 占位。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("On Demand Rules")
    }
}

// MARK: - Profile Override（占位）
private struct ProfileOverrideSettingsView: View {
    var body: some View {
        Form {
            Text("Profile Override 占位。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Profile Override")
    }
}

// MARK: - Service Log（占位，可后续接日志页）
private struct ServiceLogSettingsView: View {
    var body: some View {
        Form {
            Text("Service Log 占位，可跳转到日志视图。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Service Log")
    }
}
