//
//  SettingsView.swift
//  MeshFluxMac
//
//  与 sing-box SettingView 对齐：多 Tab（App / Core / Packet Tunnel / On Demand Rules / Profile Override / About / Debug）。
//  商业化版本隐藏日志与 Debug 入口（AppConfig.showLogsInUI = false）。
//

import SwiftUI
import VPNLibrary
#if os(macOS)
import ServiceManagement
#endif

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
                Link(destination: URL(string: "https://meshnetprotocol.github.io/")!) {
                    Label("Documentation", systemImage: "doc.on.doc.fill")
                }
                .foregroundStyle(Color.accentColor)
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

// MARK: - App（仅保留 Start At Login）
private struct AppSettingsView: View {
    @State private var startAtLogin = false
    @State private var isLoading = true
    @State private var alertMessage: String?
    @State private var showAlert = false

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
                    } footer: {
                        Text("Launch the application when the system is logged in. If enabled at the same time as Show in Menu Bar and Keep Menu Bar in Background, the application interface will not be opened automatically.")
                    }
                    #endif
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("App")
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
        await MainActor.run {
            startAtLogin = start
            isLoading = false
        }
        #else
        await MainActor.run { isLoading = false }
        #endif
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

// MARK: - Core（UI 对齐 sing-box CoreView，仅界面不实现逻辑）
private struct CoreSettingsView: View {
    @State private var version = "—"
    @State private var dataSize = "—"
    @State private var disableDeprecatedWarnings = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Data Size", value: dataSize)
            }

            Section {
                Toggle("Disable Deprecated Warnings", isOn: $disableDeprecatedWarnings)
            } footer: {
                Text("Do not show warnings about usages of deprecated features.")
            }

            Section("Working Directory") {
                #if os(macOS)
                Button {
                    // 仅 UI，不实现
                } label: {
                    Label("Open", systemImage: "macwindow.and.cursorarrow")
                }
                #endif
                Button(role: .destructive) {
                    // 仅 UI，不实现
                } label: {
                    Label("Destroy", systemImage: "trash.fill")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Core")
    }
}

// MARK: - Packet Tunnel（与 sing-box PacketTunnelView 对齐）
private struct PacketTunnelSettingsView: View {
    @State private var isLoading = true
    @State private var ignoreMemoryLimit = false
    @State private var includeAllNetworks = false
    @State private var excludeAPNs = false
    @State private var excludeCellularServices = false
    @State private var excludeLocalNetworks = false
    @State private var enforceRoutes = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        Toggle("Ignore Memory Limit", isOn: $ignoreMemoryLimit)
                            .onChange(of: ignoreMemoryLimit) { newValue in
                                Task { await SharedPreferences.ignoreMemoryLimit.set(newValue) }
                            }
                    } footer: {
                        Text("Do not enforce memory limits on sing-box. Will cause OOM on non-jailbroken iOS and tvOS devices.")
                    }

                    Section {
                        Toggle("includeAllNetworks", isOn: $includeAllNetworks)
                            .onChange(of: includeAllNetworks) { newValue in
                                Task { await SharedPreferences.includeAllNetworks.set(newValue) }
                            }
                        Toggle("excludeAPNs", isOn: $excludeAPNs)
                            .onChange(of: excludeAPNs) { newValue in
                                Task { await SharedPreferences.excludeAPNs.set(newValue) }
                            }
                        Toggle("excludeCellularServices", isOn: $excludeCellularServices)
                            .onChange(of: excludeCellularServices) { newValue in
                                Task { await SharedPreferences.excludeCellularServices.set(newValue) }
                            }
                        Toggle("excludeLocalNetworks", isOn: $excludeLocalNetworks)
                            .onChange(of: excludeLocalNetworks) { newValue in
                                Task { await SharedPreferences.excludeLocalNetworks.set(newValue) }
                            }
                        Toggle("enforceRoutes", isOn: $enforceRoutes)
                            .onChange(of: enforceRoutes) { newValue in
                                Task { await SharedPreferences.enforceRoutes.set(newValue) }
                            }
                    }

                    Section {
                        Button(role: .destructive) {
                            Task {
                                await SharedPreferences.resetPacketTunnel()
                                isLoading = true
                                await loadSettings()
                            }
                        } label: {
                            Label("Reset", systemImage: "eraser.fill")
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Packet Tunnel")
        .onAppear { Task { await loadSettings() } }
    }

    private func loadSettings() async {
        ignoreMemoryLimit = await SharedPreferences.ignoreMemoryLimit.get()
        includeAllNetworks = await SharedPreferences.includeAllNetworks.get()
        excludeAPNs = await SharedPreferences.excludeAPNs.get()
        excludeCellularServices = await SharedPreferences.excludeCellularServices.get()
        excludeLocalNetworks = await SharedPreferences.excludeLocalNetworks.get()
        enforceRoutes = await SharedPreferences.enforceRoutes.get()
        await MainActor.run { isLoading = false }
    }
}

// MARK: - On Demand Rules（与 sing-box OnDemandRulesView 对齐）
private struct OnDemandRulesSettingsView: View {
    @State private var isLoading = true
    @State private var alwaysOn = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        Toggle("Always On", isOn: $alwaysOn)
                            .onChange(of: alwaysOn) { newValue in
                                Task { await SharedPreferences.alwaysOn.set(newValue) }
                            }
                    } footer: {
                        Text("Implement always-on via on-demand rules. You cannot disable VPN in system settings. To stop the service manually, use the in-app interface or delete the VPN profile.")
                    }

                    Section {
                        Button(role: .destructive) {
                            Task {
                                await SharedPreferences.resetOnDemandRules()
                                isLoading = true
                                await loadSettings()
                            }
                        } label: {
                            Label("Reset", systemImage: "eraser.fill")
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("On Demand Rules")
        .onAppear { Task { await loadSettings() } }
    }

    private func loadSettings() async {
        alwaysOn = await SharedPreferences.alwaysOn.get()
        await MainActor.run { isLoading = false }
    }
}

// MARK: - Profile Override（UI 对齐 sing-box ProfileOverrideView，仅界面不实现逻辑）
private struct ProfileOverrideSettingsView: View {
    @State private var excludeDefaultRoute = false
    @State private var autoRouteUseSubRangesByDefault = false
    @State private var excludeAPNsRoute = false

    var body: some View {
        Form {
            Section {
                Toggle("Hide VPN Icon", isOn: $excludeDefaultRoute)
            } footer: {
                Text("Append `0.0.0.0/31` and `::/127` to `route_exclude_address` if not exists.")
            }

            Section {
                Toggle("No Default Route", isOn: $autoRouteUseSubRangesByDefault)
            } footer: {
                Text("By default, segment routing is used in `auto_route` instead of global routing. If `<route_address/route_exclude_address>` exists in the configuration, this item will not take effect on the corresponding network (commonly used to resolve HomeKit compatibility issues).")
            }

            Section {
                Toggle("Exclude APNs Route", isOn: $excludeAPNsRoute)
            } footer: {
                Text("Append `push.apple.com` to `bypass_domain`, and `17.0.0.0/8` to `route_exclude_address`.")
            }

            Section {
                Button(role: .destructive) {
                    // 仅 UI，不实现
                } label: {
                    Label("Reset", systemImage: "eraser.fill")
                }
            }
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
