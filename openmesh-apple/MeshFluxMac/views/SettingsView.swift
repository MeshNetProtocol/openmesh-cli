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

// MARK: - App（与 sing-box MacAppView 对齐：Start At Login、Show in Menu Bar、Keep Menu Bar in Background；日志为扩展）
private struct AppSettingsView: View {
    @Environment(\.showMenuBarExtra) private var showMenuBarExtra
    @State private var startAtLogin = false
    @State private var menuBarExtraInBackground = false
    @State private var maxLogLines = 300
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

                    // Show in Menu Bar / Keep Menu Bar in Background：功能已注销，点击仅打日志，避免用户困惑
                    Section {
                        Toggle("Show in Menu Bar", isOn: Binding(
                            get: { showMenuBarExtra.wrappedValue },
                            set: { newValue in
                                NSLog("MeshFlux: Show in Menu Bar toggled to %@ (ignored, feature disabled)", newValue ? "ON" : "OFF")
                            }
                        ))
                        if showMenuBarExtra.wrappedValue {
                            Toggle("Keep Menu Bar in Background", isOn: Binding(
                                get: { menuBarExtraInBackground },
                                set: { newValue in
                                    NSLog("MeshFlux: Keep Menu Bar in Background toggled to %@ (ignored, feature disabled)", newValue ? "ON" : "OFF")
                                }
                            ))
                        }
                    } footer: {
                        Text("以上两项已暂时关闭，以免造成困惑；点击仅会记录日志，不会生效。")
                    }
                    #endif

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
        let menuBar = await SharedPreferences.menuBarExtraInBackground.get()
        #endif
        let lines = await SharedPreferences.maxLogLines.get()
        await MainActor.run {
            #if os(macOS)
            startAtLogin = start
            menuBarExtraInBackground = menuBar
            #endif
            maxLogLines = lines
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
