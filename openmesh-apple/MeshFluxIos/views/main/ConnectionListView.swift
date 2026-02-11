//
//  ConnectionListView.swift
//  MeshFluxIos
//
//  连接列表子页面：从 Home 进入，展示当前连接（协议、目标、流量、状态）。
//

import SwiftUI
import OpenMeshGo

struct ConnectionListView: View {
    @ObservedObject var connectionClient: ConnectionCommandClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        NavigationView {
            Group {
                if connectionClient.connections == nil {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if connectionClient.connections?.isEmpty == true {
                    Text("暂无连接")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array((connectionClient.connections ?? []).enumerated()), id: \.offset) { _, conn in
                                ConnectionRowView(connection: conn)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("状态", selection: $connectionClient.connectionStateFilter) {
                            ForEach(ConnectionStateFilter.allCases) { f in
                                Text(f.name).tag(f)
                            }
                        }
                        .onChange(of: connectionClient.connectionStateFilter) { _ in
                            connectionClient.filterConnectionsNow()
                        }
                        Picker("排序", selection: $connectionClient.connectionSort) {
                            ForEach(ConnectionSort.allCases) { s in
                                Text(s.name).tag(s)
                            }
                        }
                        .onChange(of: connectionClient.connectionSort) { _ in
                            connectionClient.filterConnectionsNow()
                        }
                        Button("关闭全部连接", role: .destructive) {
                            Task { await closeAll() }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.circle")
                    }
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                if let alertMessage { Text(alertMessage) }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            connectionClient.connect()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                connectionClient.connect()
            } else {
                connectionClient.disconnect()
            }
        }
        .onDisappear {
            connectionClient.disconnect()
        }
    }

    private func closeAll() async {
        do {
            try connectionClient.closeConnections()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

private struct ConnectionRowView: View {
    let connection: OMLibboxConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(connection.network.uppercased()) \(connection.displayDestination())")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(connection.closedAt > 0 ? "已关闭" : "活动中")
                    .font(.caption2)
                    .foregroundColor(connection.closedAt > 0 ? .red : .green)
            }
            HStack {
                Text("↑ \(OMLibboxFormatBytes(connection.uplinkTotal)) ↓ \(OMLibboxFormatBytes(connection.downlinkTotal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(connection.outbound)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}
