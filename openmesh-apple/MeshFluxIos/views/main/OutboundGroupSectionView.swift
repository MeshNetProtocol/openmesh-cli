//
//  OutboundGroupSectionView.swift
//  MeshFluxIos
//
//  出站组列表：展示节点、延迟、当前选中，支持切换节点与测速。仅 VPN 连接时显示。
//

import SwiftUI

struct OutboundGroupSectionView: View {
    @ObservedObject var groupClient: GroupCommandClient
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("出站组")
                .font(.headline)

            if groupClient.groups.isEmpty {
                Text("加载中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(groupClient.groups) { group in
                    OutboundGroupCardView(
                        group: group,
                        groupClient: groupClient,
                        alertMessage: $alertMessage,
                        showAlert: $showAlert
                    )
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let alertMessage { Text(alertMessage) }
        }
    }
}

private struct OutboundGroupCardView: View {
    let group: OutboundGroupModel
    @ObservedObject var groupClient: GroupCommandClient
    @Binding var alertMessage: String?
    @Binding var showAlert: Bool
    @State private var urlTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.tag)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(group.type.isEmpty ? "—" : group.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(group.items.count) 项")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)

                Button {
                    Task { await toggleExpand() }
                } label: {
                    Image(systemName: group.isExpand ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await doURLTest() }
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(urlTesting ? .gray : .orange)
                }
                .buttonStyle(.plain)
                .disabled(urlTesting)
            }
            .padding(8)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(8)

            if group.isExpand {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(group.items) { item in
                        OutboundGroupItemRow(
                            item: item,
                            isSelected: group.selected == item.tag,
                            selectable: group.selectable,
                            groupTag: group.tag,
                            groupClient: groupClient,
                            alertMessage: $alertMessage,
                            showAlert: $showAlert
                        )
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func toggleExpand() async {
        do {
            try await groupClient.setGroupExpand(groupTag: group.tag, isExpand: !group.isExpand)
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func doURLTest() async {
        urlTesting = true
        defer { urlTesting = false }
        do {
            try await groupClient.urlTest(groupTag: group.tag)
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

private struct OutboundGroupItemRow: View {
    let item: OutboundGroupItemModel
    let isSelected: Bool
    let selectable: Bool
    let groupTag: String
    @ObservedObject var groupClient: GroupCommandClient
    @Binding var alertMessage: String?
    @Binding var showAlert: Bool

    var body: some View {
        Button {
            if selectable, !isSelected {
                Task { await selectOutbound() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.tag)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
                if item.urlTestDelay > 0 {
                    Text(item.delayString)
                        .font(.caption)
                        .foregroundColor(Color(red: item.delayColor.r, green: item.delayColor.g, blue: item.delayColor.b))
                }
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!selectable || isSelected)
    }

    private func selectOutbound() async {
        do {
            try await groupClient.selectOutbound(groupTag: groupTag, outboundTag: item.tag)
            groupClient.setSelected(groupTag: groupTag, outboundTag: item.tag)
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
