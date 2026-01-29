//
//  openmeshApp.swift
//  meshflux-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation
import AppKit
import VPNLibrary
import OpenMeshGo

@main
struct openmeshApp: App {
    @StateObject private var vpnController = VPNController()

    init() {
        // LibboxSetup 使主 App 的 CommandClient 能连接 extension 的 command.sock（与 sing-box 一致）。
        configureLibbox()
    }

    private func configureLibbox() {
        let options = OMLibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.path
        options.workingPath = FilePath.workingDirectory.path
        options.tempPath = FilePath.cacheDirectory.path
        var err: NSError?
        OMLibboxSetup(options, &err)
        if let err {
            NSLog("MeshFluxMac OMLibboxSetup failed: %@", err.localizedDescription)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(vpnController: vpnController, onAppear: ensureDefaultProfileIfNeeded)
        } label: {
            Label {
                Text("MeshFlux")
            } icon: {
                statusBarIcon
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
            .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }

    private var statusBarIcon: Image {
        Image(vpnController.isConnected ? "mesh_on" : "mesh_off")
    }

    /// 首次启动时若没有任何配置，自动从 bundle 安装自带默认配置（规则 + 服务器模板）。
    /// 若用户删光了配置，可在「配置列表」空状态点击「使用默认配置」手动安装。
    private func ensureDefaultProfileIfNeeded() {
        Task {
            do {
                _ = try await DefaultProfileHelper.installDefaultProfileFromBundle()
                await MainActor.run {
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                }
            } catch {
                // Ignore; user can click "使用默认配置" in Profiles view
            }
        }
    }
}

private enum SidebarItem: String, CaseIterable {
    case dashboard = "Dashboard"
    case profiles = "配置列表"
    case settings = "设置"
    case logs = "日志"
    case server = "服务器"
}

private struct MenuContentView: View {
    @ObservedObject var vpnController: VPNController
    var onAppear: (() -> Void)?
    @State private var selection: SidebarItem? = .dashboard
    @State private var isGlobalMode: Bool = (RoutingModeStore.read() == .global)
    
    @State private var serverAddress: String = ""
    @State private var serverPort: String = ""
    @State private var serverPassword: String = ""
    @State private var serverMethod: String = "aes-256-gcm"
    @State private var showSaveSuccessAlert: Bool = false
    @State private var showSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""
    @State private var showPassword: Bool = false
    @State private var configPreview: String = ""
    @State private var configSource: String = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
                Section {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    DashboardView(vpnController: vpnController)
                case .profiles:
                    ProfilesView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogsView()
                case .server:
                    serverTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 560)
        .onAppear {
            onAppear?()
            loadServerConfig()
            loadConfigPreview()
        }
    }

    private var serverTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器配置")
                    .font(.headline)

                // 注明：此 Tab 仅影响「无配置」时的回退逻辑，建议用「配置列表」管理配置
                Text("以下设置仅在「没有选中任何配置」时由 VPN 回退使用。建议在「配置列表」中新建/编辑配置，或导入 JSON 管理服务器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)

                Text("修改 Shadowsocks 代理服务器设置（回退用）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // Server Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务器地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("例如: 192.168.1.1", text: $serverAddress)
                        .textFieldStyle(.roundedBorder)
                }

                // Server Port
                VStack(alignment: .leading, spacing: 4) {
                    Text("端口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("例如: 10086", text: $serverPort)
                        .textFieldStyle(.roundedBorder)
                }

                // Password
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("密码")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    if showPassword {
                        TextField("输入密码", text: $serverPassword)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("输入密码", text: $serverPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Encryption Method
                VStack(alignment: .leading, spacing: 4) {
                    Text("加密方式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $serverMethod) {
                        ForEach(SingboxConfigStore.ServerConfig.supportedMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // Save Button
                Button(action: {
                    saveServerConfig()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("保存配置")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConfigValid)
                .padding(.top, 8)

                Divider()
                    .padding(.vertical, 8)

                // Config Preview Section
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("当前配置预览")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(configSource)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    ScrollView {
                        Text(configPreview)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    Button(action: {
                        loadConfigPreview()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新预览")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }

                Text("提示：保存后 VPN 会自动重新加载配置")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .alert("保存成功 ✅", isPresented: $showSaveSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("服务器配置已保存到 App Group，VPN 将自动重新加载。\n\n请查看下方「当前配置预览」确认修改。")
        }
        .alert("保存失败 ❌", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private var isConfigValid: Bool {
        !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !serverPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(serverPort) != nil &&
        !serverPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadServerConfig() {
        let config = SingboxConfigStore.readServerConfig()
        serverAddress = config.server
        serverPort = config.serverPort > 0 ? String(config.serverPort) : ""
        serverPassword = config.password
        serverMethod = config.method.isEmpty ? "aes-256-gcm" : config.method
    }
    
    private func loadConfigPreview() {
        let fileManager = FileManager.default
        
        // Try App Group config first
        if let configURL = SingboxConfigStore.configFileURL(),
           fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let jsonString = formatJSON(data) {
            configPreview = jsonString
            configSource = "📁 App Group (用户配置)"
            return
        }
        
        // Fall back to bundled config
        if let bundledURL = SingboxConfigStore.bundledConfigURL(),
           let data = try? Data(contentsOf: bundledURL),
           let jsonString = formatJSON(data) {
            configPreview = jsonString
            configSource = "📦 Bundle (默认配置)"
            return
        }
        
        configPreview = "无法读取配置文件"
        configSource = "⚠️ 错误"
    }
    
    private func formatJSON(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(decoding: prettyData, as: UTF8.self)
    }

    private func saveServerConfig() {
        guard let port = Int(serverPort) else {
            saveErrorMessage = "端口必须是数字"
            showSaveErrorAlert = true
            return
        }

        let config = SingboxConfigStore.ServerConfig(
            server: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            serverPort: port,
            password: serverPassword,
            method: serverMethod
        )

        do {
            try SingboxConfigStore.saveServerConfig(config)
            // Reload preview to show the saved config
            loadConfigPreview()
            showSaveSuccessAlert = true
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
