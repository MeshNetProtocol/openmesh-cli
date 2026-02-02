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
                ZStack(alignment: .center) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(groupClient.groups) { group in
                                GroupRowView(
                                    group: group,
                                    groupClient: groupClient,
                                    onURLTest: {
                                        testingTag = group.tag  // 立即标记，防止连续点击
                                        await runURLTest(groupTag: group.tag)
                                    },
                                    isTesting: testingTag == group.tag
                                )
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(testingTag != nil)

                    // 测速中：半透明遮罩铺满区域 + 居中转圈，阻止与出站组区域交互、防止连续点击，完成后自动消失
                    if testingTag != nil {
                        Color.black.opacity(0.35)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .allowsHitTesting(true)
                        ProgressView("测速中…")
                            .frame(width: 120, height: 80)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
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
    /// 成功时不弹窗，仅保持转圈直至完成并自动消失；失败时才弹 alert。
    @MainActor
    private func runURLTest(groupTag: String) async {
        testingTag = groupTag
        defer { testingTag = nil }
        // 短暂让出，确保「测速中…」遮罩先渲染出来（MainActor.yield 部分 Swift 版本不可用，用短 sleep 替代）
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        let start = CFAbsoluteTimeGetCurrent()
        do {
            try await groupClient.urlTest(groupTag: groupTag)
            // 成功：不弹 alert，转圈由 defer 清除，列表会通过 onWriteGroups 自动更新延迟
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
        // 最短显示约 0.4 秒，避免测速很快时 loading 一闪而过
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        if elapsed < 0.4 {
            try? await Task.sleep(nanoseconds: UInt64((0.4 - elapsed) * 1_000_000_000))
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
                            .frame(width: 24, height: 24)
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
