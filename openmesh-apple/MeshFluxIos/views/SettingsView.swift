//
//  SettingsView.swift
//  MeshFluxIos
//
//  与 MeshFluxMac 设置页对齐：About。
//

import SwiftUI
import NetworkExtension
import VPNLibrary

struct SettingsView: View {
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
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
        .onAppear { Task { await loadSettings() } }
    }

    private func loadSettings() async {
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        if excludeLocal == false {
            await SharedPreferences.excludeLocalNetworks.set(true)
        }
        await MainActor.run { isLoading = false }
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
