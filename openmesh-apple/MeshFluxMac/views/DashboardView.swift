//
//  DashboardView.swift
//  MeshFluxMac
//
//  Phase 3: Dashboard — current profile, status, Start/Stop via ExtensionProfile.
//

import SwiftUI
import NetworkExtension
import VPNLibrary

struct DashboardView: View {
    @ObservedObject var vpnController: VPNController
    @State private var currentProfileName: String = ""
    @State private var selectedProfileID: Int64 = -1
    @State private var emptyProfiles: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dashboard")
                .font(.headline)

            if !currentProfileName.isEmpty {
                Text("当前配置：\(currentProfileName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if emptyProfiles {
                Text("暂无配置。请先在「配置列表」中点击「使用默认配置」或「新建配置」。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if selectedProfileID < 0 {
                Text("未选择配置。请在「配置列表」中选择一个配置。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: Binding(
                get: { vpnController.isConnected },
                set: { _ in vpnController.toggleVPN() }
            )) {
                Text(vpnController.isConnected ? "已连接" : "连接 VPN")
            }
            .toggleStyle(.switch)
            .disabled(vpnController.isConnecting || emptyProfiles || selectedProfileID < 0)

            if vpnController.isConnecting {
                ProgressView("连接中...")
                    .progressViewStyle(.circular)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadCurrentProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            loadCurrentProfile()
        }
    }

    private func loadCurrentProfile() {
        Task {
            let list = try? await ProfileManager.list()
            let id = await SharedPreferences.selectedProfileID.get()
            await MainActor.run {
                emptyProfiles = (list?.isEmpty ?? true)
                selectedProfileID = id
                if id >= 0, let profile = list?.first(where: { $0.mustID == id }) {
                    currentProfileName = profile.name
                } else {
                    currentProfileName = ""
                }
            }
        }
    }
}

extension Notification.Name {
    static let selectedProfileDidChange = Notification.Name("selectedProfileDidChange")
}
