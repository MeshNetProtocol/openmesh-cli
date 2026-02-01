//
//  DashboardView.swift
//  MeshFluxMac
//
//  Dashboard：当前配置、状态网格（与 sing-box ExtensionStatusView 对齐）、VPN 开关。
//

import SwiftUI
import NetworkExtension
import VPNLibrary
import OpenMeshGo

struct DashboardView: View {
    @ObservedObject var vpnController: VPNController
    @StateObject private var statusClient = StatusCommandClient()
    @State private var currentProfileName: String = ""
    @State private var selectedProfileID: Int64 = -1
    @State private var emptyProfiles: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    private let statusColumnCount = 4
    private let statusMinCardWidth: CGFloat = 125

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.semibold)

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

                // 与 sing-box ExtensionStatusView 一致：连接时显示状态网格（内存、协程、连接数、流量）
                if vpnController.isConnected {
                    ExtensionStatusBlock(status: statusClient.status)
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

                Spacer(minLength: 32)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadCurrentProfile()
            if vpnController.isConnected { statusClient.connect() }
        }
        .onDisappear {
            statusClient.disconnect()
        }
        .onChange(of: vpnController.isConnected) { connected in
            if connected { statusClient.connect() }
            else { statusClient.disconnect() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, vpnController.isConnected { statusClient.connect() }
            else if phase != .active { statusClient.disconnect() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            loadCurrentProfile()
        }
    }

    private func loadCurrentProfile() {
        Task {
            let list = try? await ProfileManager.list()
            var id = await SharedPreferences.selectedProfileID.get()
            // When preference was cleared (e.g. corrupted JSON repair), id is -1 but we may have profiles: auto-select first.
            if id < 0, let list = list, !list.isEmpty {
                await SharedPreferences.selectedProfileID.set(list[0].mustID)
                id = list[0].mustID
            }
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

// MARK: - ExtensionStatusBlock（与 sing-box ExtensionStatusView 对齐：状态网格；数据来自 StatusCommandClient ↔ extension command.sock）
private struct ExtensionStatusBlock: View {
    let status: OMLibboxStatusMessage?

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            if let msg = status {
                StatusCard(title: "状态") {
                    StatusRow(name: "内存", value: OMLibboxFormatMemoryBytes(msg.memory))
                    StatusRow(name: "协程", value: "\(msg.goroutines)")
                }
                StatusCard(title: "连接数") {
                    StatusRow(name: "入站", value: "\(msg.connectionsIn)")
                    StatusRow(name: "出站", value: "\(msg.connectionsOut)")
                }
                if msg.trafficAvailable {
                    StatusCard(title: "流量") {
                        StatusRow(name: "上行", value: "\(OMLibboxFormatBytes(msg.uplink))/s")
                        StatusRow(name: "下行", value: "\(OMLibboxFormatBytes(msg.downlink))/s")
                    }
                    StatusCard(title: "流量合计") {
                        StatusRow(name: "上行", value: OMLibboxFormatBytes(msg.uplinkTotal))
                        StatusRow(name: "下行", value: OMLibboxFormatBytes(msg.downlinkTotal))
                    }
                }
            } else {
                StatusCard(title: "状态") {
                    StatusRow(name: "内存", value: "...")
                    StatusRow(name: "协程", value: "...")
                }
                StatusCard(title: "连接数") {
                    StatusRow(name: "入站", value: "...")
                    StatusRow(name: "出站", value: "...")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct StatusCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(minWidth: 140, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
}

private struct StatusRow: View {
    private let name: String
    private let value: String

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }
}

extension Notification.Name {
    static let selectedProfileDidChange = Notification.Name("selectedProfileDidChange")
}
