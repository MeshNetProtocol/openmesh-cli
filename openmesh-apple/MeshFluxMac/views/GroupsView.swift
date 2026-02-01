//
//  GroupsView.swift
//  MeshFluxMac
//
//  出站组列表与 URL 测速（与 sing-box GroupListView / GroupView 一致）。仅 VPN 已连接时显示。
//

import SwiftUI
import VPNLibrary

struct GroupsView: View {
    @ObservedObject var vpnController: VPNController
    @StateObject private var groupClient = GroupCommandClient()
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var testingTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("出站组")
                .font(.headline)

            if !vpnController.isConnected {
                Text("请先连接 VPN，此处将显示当前配置中的出站组（selector/urltest 等）及测速。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else if !groupClient.isConnected {
                ProgressView("正在连接 extension…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupClient.groups.isEmpty {
                Text("暂无出站组。当前选中的配置中若无 selector/urltest 等出站组，此处为空。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupClient.groups) { group in
                            GroupRowView(
                                group: group,
                                groupClient: groupClient,
                                onURLTest: { await runURLTest(groupTag: group.tag) },
                                isTesting: testingTag == group.tag
                            )
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if vpnController.isConnected {
                groupClient.connect()
            }
        }
        .onDisappear {
            groupClient.disconnect()
        }
        .onChange(of: vpnController.isConnected) { connected in
            if connected {
                groupClient.connect()
            } else {
                groupClient.disconnect()
            }
        }
        .alert("出站组", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// 与 sing-box GroupView doURLTest 一致：仅调用 urlTest，不断开现有 CommandClient 连接；extension 会通过原连接推送更新后的延迟。
    private func runURLTest(groupTag: String) async {
        testingTag = groupTag
        defer { testingTag = nil }
        do {
            try await groupClient.urlTest(groupTag: groupTag)
            await MainActor.run {
                alertMessage = "测速已触发，延迟将更新在列表中。"
                showAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

private struct GroupRowView: View {
    let group: OutboundGroupModel
    @ObservedObject var groupClient: GroupCommandClient
    var onURLTest: () async -> Void
    var isTesting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.tag)
                    .font(.headline)
                Text(group.type)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(group.items.count) 项")
                    .font(.caption)
                    .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)
                Spacer()
                Button {
                    Task { await onURLTest() }
                } label: {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
                .help("URL 测速")
            }

            if !group.items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 6) {
                    ForEach(group.items) { item in
                        GroupItemRowView(
                            group: group,
                            item: item,
                            groupClient: groupClient
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// 单个出站节点行：可点击切换选中（与 sing-box GroupItemView 一致）。
private struct GroupItemRowView: View {
    let group: OutboundGroupModel
    let item: OutboundGroupItemModel
    @ObservedObject var groupClient: GroupCommandClient
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        Button {
            if group.selectable, group.selected != item.tag {
                Task { await selectOutbound() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.tag)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if group.selected == item.tag {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.accent)
                    }
                    if item.urlTestDelay > 0 {
                        Text(item.delayString)
                            .font(.caption2)
                            .foregroundColor(Color(red: item.delayColor.r, green: item.delayColor.g, blue: item.delayColor.b))
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!group.selectable || group.selected == item.tag)
        .alert("出站组", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func selectOutbound() async {
        do {
            try await groupClient.selectOutbound(groupTag: group.tag, outboundTag: item.tag)
            await MainActor.run {
                groupClient.setSelected(groupTag: group.tag, outboundTag: item.tag)
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
