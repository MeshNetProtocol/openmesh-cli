//
//  StatusCardsView.swift
//  MeshFluxIos
//
//  Dashboard 统计卡片：仅连接数、流量（不展示内存、协程）。
//

import SwiftUI
import OpenMeshGo

struct StatusCardsView: View {
    let status: OMLibboxStatusMessage?

    var body: some View {
        if let msg = status {
            HStack(alignment: .top, spacing: 12) {
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
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                StatusCard(title: "连接数") {
                    StatusRow(name: "入站", value: "…")
                    StatusRow(name: "出站", value: "…")
                }
                StatusCard(title: "流量") {
                    StatusRow(name: "上行", value: "…")
                    StatusRow(name: "下行", value: "…")
                }
            }
        }
    }
}

private struct StatusCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(minWidth: 100, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

private struct StatusRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}
