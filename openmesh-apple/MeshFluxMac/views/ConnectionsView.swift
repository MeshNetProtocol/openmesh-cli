//
//  ConnectionsView.swift
//  MeshFluxMac
//
//  连接列表页（与 sing-box ConnectionListView 对齐）：筛选、排序、搜索、关闭全部/单条。
//

import SwiftUI
import OpenMeshGo
import VPNLibrary

struct ConnectionsView: View {
    @ObservedObject var vpnController: VPNController
    @StateObject private var commandClient = ConnectionCommandClient()
    @State private var list: [ConnectionModel] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var alertMessage: String?
    @State private var showAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if list.isEmpty {
                Text("暂无连接")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredList, id: \.listHash) { conn in
                                ConnectionRowView(connection: conn, commandClient: commandClient) {
                                    alertMessage = $0
                                    showAlert = true
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationDestination(for: ConnectionModel.self) { conn in
                        ConnectionDetailsView(connection: conn)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索目标/域名")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("状态", selection: $commandClient.connectionStateFilter) {
                        ForEach(ConnectionStateFilter.allCases) { f in
                            Text(f.name).tag(f)
                        }
                    }
                    Picker("排序", selection: $commandClient.connectionSort) {
                        ForEach(ConnectionSort.allCases) { s in
                            Text(s.name).tag(s)
                        }
                    }
                    Button("关闭全部连接", role: .destructive) {
                        do {
                            try commandClient.closeConnections()
                        } catch {
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.circle")
                }
            }
        }
        .alert("错误", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "未知错误")
        }
        .onAppear {
            if vpnController.isConnected { commandClient.connect() }
            else { isLoading = false }
        }
        .onDisappear {
            commandClient.disconnect()
        }
        .onChange(of: vpnController.isConnected) { connected in
            if connected { commandClient.connect() }
            else { commandClient.disconnect(); isLoading = false }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, vpnController.isConnected { commandClient.connect() }
            else if phase != .active { commandClient.disconnect() }
        }
        .onChange(of: commandClient.connectionStateFilter) { _ in
            commandClient.filterConnectionsNow()
            Task {
                await SharedPreferences.connectionStateFilter.set(commandClient.connectionStateFilter.rawValue)
            }
        }
        .onChange(of: commandClient.connectionSort) { _ in
            commandClient.filterConnectionsNow()
            Task {
                await SharedPreferences.connectionSort.set(commandClient.connectionSort.rawValue)
            }
        }
        .onReceive(commandClient.$connections) { goList in
            if let goList {
                list = connectionModels(from: goList)
                isLoading = false
            }
        }
        .task {
            let f = await SharedPreferences.connectionStateFilter.get()
            let s = await SharedPreferences.connectionSort.get()
            if let ff = ConnectionStateFilter(rawValue: f) { commandClient.connectionStateFilter = ff }
            if let ss = ConnectionSort(rawValue: s) { commandClient.connectionSort = ss }
        }
    }

    private var filteredList: [ConnectionModel] {
        let t = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return list }
        return list.filter { $0.matchesSearch(searchText) }
    }
}
