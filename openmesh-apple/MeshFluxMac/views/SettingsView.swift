//
//  SettingsView.swift
//  MeshFluxMac
//
//  VPN 相关设置：Always On、Include All Networks、日志行数等。数据来自 SharedPreferences。
//

import SwiftUI
import VPNLibrary

struct SettingsView: View {
    @State private var alwaysOn: Bool = false
    @State private var includeAllNetworks: Bool = false
    @State private var maxLogLines: Int = 300
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置")
                .font(.headline)

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
                .formStyle(.grouped)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadSettings()
        }
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
