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
            HStack {
                Text("出站组")
                    .font(.headline)
                Spacer()
                if groupClient.isConnected {
                    Text("已连接 extension")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        groupClient.disconnect()
                        groupClient.connect()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

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

    private func runURLTest(groupTag: String) async {
        testingTag = groupTag
        defer { testingTag = nil }
        do {
            try await groupClient.urlTest(groupTag: groupTag)
            await MainActor.run {
                alertMessage = "测速已触发，请稍候查看延迟更新。"
                showAlert = true
            }
            groupClient.disconnect()
            groupClient.connect()
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
                        HStack {
                            Text(item.tag)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(item.delayString)
                                .font(.caption2)
                                .foregroundColor(Color(red: item.delayColor.r, green: item.delayColor.g, blue: item.delayColor.b))
                        }
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
