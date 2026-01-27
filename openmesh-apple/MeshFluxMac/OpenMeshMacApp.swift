//
//  openmeshApp.swift
//  meshflux-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation
import AppKit

@main
struct openmeshApp: App {
    @StateObject private var vpnManager = VPNManager()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }

    var body: some Scene {
        // 2. 使用 MenuBarExtra 代替 WindowGroup
        MenuBarExtra {
            MenuContentView(vpnManager: vpnManager)
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
        Image(vpnManager.isConnected ? "mesh_on" : "mesh_off")
    }
}

private struct MenuContentView: View {
    @ObservedObject var vpnManager: VPNManager
    @State private var isGlobalMode: Bool = (RoutingModeStore.read() == .global)
    
    // Server config states
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
    
    // Custom URL states
    @State private var customRuleURL: String = ""
    @State private var showURLSaveSuccessAlert: Bool = false

    var body: some View {
        TabView {
            vpnTab
                .tabItem { Text("VPN") }
            serverTab
                .tabItem { Text("服务器") }
            customURLTab
                .tabItem { Text("自定义") }
        }
        .frame(width: 400, height: 580)
        .onAppear {
            loadServerConfig()
            loadConfigPreview()
        }
    }

    private var vpnTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MeshFlux VPN")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { isGlobalMode },
                set: { newValue in
                    isGlobalMode = newValue
                    RoutingModeStore.write(newValue ? .global : .rule)
                }
            )) {
                Text(isGlobalMode ? "路由：全局" : "路由：规则")
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(
                get: { vpnManager.isConnected },
                set: { _ in vpnManager.toggleVPN() }
            )) {
                Text(vpnManager.isConnected ? "断开连接" : "连接 VPN")
            }
            .toggleStyle(.switch)

            if vpnManager.isConnecting {
                ProgressView("正在连接...")
                    .progressViewStyle(.circular)
            }

            Text(isGlobalMode ? "全局模式：所有流量走代理" : "规则模式：命中规则走代理，未命中走直连")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("退出应用") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
    }

    private var serverTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器配置")
                    .font(.headline)

                Text("修改 Shadowsocks 代理服务器设置")
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
    
    private var customURLTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义规则")
                .font(.headline)

            Text("输入自定义规则 URL，将会被添加到路由规则中")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("请输入规则 URL", text: $customRuleURL)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)

            Button(action: {
                saveCustomRule()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存规则")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(customRuleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 8)

            Spacer()

            Text("提示：保存后需要重新连接 VPN 才能生效")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .alert("保存成功", isPresented: $showURLSaveSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("自定义规则 URL 已保存")
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
    
    private func saveCustomRule() {
        // TODO: 实际保存逻辑将在后续实现
        // 目前只显示保存成功提示
        showURLSaveSuccessAlert = true
    }
}
