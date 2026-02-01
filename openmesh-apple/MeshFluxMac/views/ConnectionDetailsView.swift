//
//  ConnectionDetailsView.swift
//  MeshFluxMac
//
//  单条连接详情（与 sing-box ConnectionDetailsView 对齐）。
//

import SwiftUI
import OpenMeshGo
import VPNLibrary

struct ConnectionDetailsView: View {
    let connection: ConnectionModel

    private var dateFormat: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("状态", value: connection.closedAt == nil ? "活动中" : "已关闭")
                LabeledContent("创建时间", value: dateFormat.string(from: connection.createdAt))
                if let closedAt = connection.closedAt {
                    LabeledContent("关闭时间", value: dateFormat.string(from: closedAt))
                }
                LabeledContent("上行", value: OMLibboxFormatBytes(connection.uploadTotal))
                LabeledContent("下行", value: OMLibboxFormatBytes(connection.downloadTotal))
            }
            Section("元数据") {
                LabeledContent("入站", value: connection.inbound)
                LabeledContent("入站类型", value: connection.inboundType)
                LabeledContent("IP 版本", value: "\(connection.ipVersion)")
                LabeledContent("网络", value: connection.network.uppercased())
                LabeledContent("来源", value: connection.source)
                LabeledContent("目标", value: connection.destination)
                if !connection.domain.isEmpty {
                    LabeledContent("域名", value: connection.domain)
                }
                if !connection.protocolName.isEmpty {
                    LabeledContent("协议", value: connection.protocolName)
                }
                if !connection.user.isEmpty {
                    LabeledContent("用户", value: connection.user)
                }
                if !connection.fromOutbound.isEmpty {
                    LabeledContent("来自出站", value: connection.fromOutbound)
                }
                if !connection.rule.isEmpty {
                    LabeledContent("匹配规则", value: connection.rule)
                }
                LabeledContent("出站", value: connection.outbound)
                LabeledContent("出站类型", value: connection.outboundType)
                if connection.chain.count > 1 {
                    LabeledContent("链", value: connection.chain.reversed().joined(separator: " / "))
                }
            }
        }
        .navigationTitle("连接详情")
    }
}
