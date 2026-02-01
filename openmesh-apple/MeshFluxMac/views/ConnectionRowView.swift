//
//  ConnectionRowView.swift
//  MeshFluxMac
//
//  单条连接行（与 sing-box ConnectionView 对齐）：展示目标、状态、流量、右键关闭。
//

import SwiftUI
import OpenMeshGo
import VPNLibrary

struct ConnectionRowView: View {
    let connection: ConnectionModel
    @ObservedObject var commandClient: ConnectionCommandClient
    var onError: (String) -> Void

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func formatInterval(created: Date, closed: Date) -> String {
        OMLibboxFormatDuration(Int64((closed.timeIntervalSince1970 - created.timeIntervalSince1970) * 1000))
    }

    var body: some View {
        NavigationLink(value: connection) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("\(connection.network.uppercased()) \(connection.displayDestination)")
                        .font(.caption.monospaced().bold())
                    Spacer()
                    if connection.closedAt == nil {
                        Text("活动中")
                            .foregroundStyle(.green)
                            .font(.caption2)
                    } else {
                        Text("已关闭")
                            .foregroundStyle(.red)
                            .font(.caption2)
                    }
                }
                HStack(alignment: .top) {
                    if let closedAt = connection.closedAt {
                        VStack(alignment: .leading) {
                            Text("↑ \(OMLibboxFormatBytes(connection.uploadTotal))")
                            Text("↓ \(OMLibboxFormatBytes(connection.downloadTotal))")
                        }
                        .font(.caption2)
                        VStack(alignment: .leading) {
                            Text(format(connection.createdAt))
                            Text(formatInterval(created: connection.createdAt, closed: closedAt))
                        }
                        .font(.caption2)
                    } else {
                        VStack(alignment: .leading) {
                            Text("↑ \(OMLibboxFormatBytes(connection.upload))/s")
                            Text("↓ \(OMLibboxFormatBytes(connection.download))/s")
                        }
                        .font(.caption2)
                        VStack(alignment: .leading) {
                            Text(OMLibboxFormatBytes(connection.uploadTotal))
                            Text(OMLibboxFormatBytes(connection.downloadTotal))
                        }
                        .font(.caption2)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(connection.inboundType)/\(connection.inbound)")
                            .font(.caption2)
                        if connection.closedAt == nil, let first = connection.chain.first {
                            Text(first)
                                .font(.caption2)
                        } else {
                            Text(connection.chain.reversed().joined(separator: "/"))
                                .font(.caption2)
                        }
                    }
                }
                .font(.caption.monospaced())
            }
            .foregroundStyle(.primary)
            .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if connection.closedAt == nil {
                Button("关闭", role: .destructive) {
                    do {
                        try commandClient.closeConnection(id: connection.id)
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            }
        }
    }
}
