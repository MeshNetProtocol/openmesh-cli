//
//  LogsView.swift
//  MeshFluxMac
//
//  日志页：优先通过 command.sock 实时流显示 extension 日志；未连接时回退到读取 stderr.log。
//  仅当 VPN 已连接时 extension 才会创建 command.sock，故在此情况下才尝试连接实时流。
//

import SwiftUI
import VPNLibrary

struct LogsView: View {
    @ObservedObject var vpnController: VPNController
    @StateObject private var logClient = LogCommandClient(maxLines: 500)
    @State private var fileFallbackContent: String = ""
    @State private var isLoadingFile = false
    @State private var lastFileUpdated: Date?
    @State private var useRealtime: Bool = true

    private var showingRealtime: Bool {
        useRealtime && logClient.isConnected
    }

    private var vpnConnected: Bool {
        vpnController.isConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日志")
                    .font(.headline)
                Spacer()
                if showingRealtime {
                    Text("实时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if showingRealtime {
                        logClient.disconnect()
                        logClient.connect()
                    } else {
                        loadLogContentFromFile()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingFile)
            }

            if !showingRealtime, let date = lastFileUpdated {
                Text("最后更新：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showingRealtime {
                if logClient.logList.isEmpty {
                    Text("暂无日志（已连接 extension，等待日志输出）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(logClient.logList.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: logClient.logList.count) { newCount in
                            if newCount > 0 {
                                reader.scrollTo(newCount - 1, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            if logClient.logList.count > 0 {
                                reader.scrollTo(logClient.logList.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            } else if isLoadingFile {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vpnConnected {
                Text("请先连接 VPN 以查看实时日志。\n\n连接后本页会自动拉取实时日志；也可点击「刷新」读取历史 stderr.log。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else if fileFallbackContent.isEmpty {
                Text("无法连接 extension 实时流。\n\n请点击「刷新」重试，或读取 stderr.log。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else {
                ScrollView {
                    Text(fileFallbackContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if vpnConnected {
                logClient.connect()
            }
            if !showingRealtime {
                loadLogContentFromFile()
            }
        }
        .onChange(of: vpnController.isConnected) { connected in
            if connected {
                logClient.connect()
            } else {
                logClient.disconnect()
            }
        }
        .onDisappear {
            logClient.disconnect()
        }
    }

    private func loadLogContentFromFile() {
        isLoadingFile = true
        Task {
            defer { Task { @MainActor in isLoadingFile = false } }
            guard let cacheDir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)?
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true) else {
                await MainActor.run { fileFallbackContent = ""; lastFileUpdated = Date() }
                return
            }
            let stderrURL = cacheDir.appendingPathComponent("stderr.log", isDirectory: false)
            guard FileManager.default.fileExists(atPath: stderrURL.path),
                  let data = try? Data(contentsOf: stderrURL),
                  let text = String(data: data, encoding: .utf8) else {
                await MainActor.run {
                    fileFallbackContent = ""
                    lastFileUpdated = Date()
                }
                return
            }
            let maxLines = await SharedPreferences.maxLogLines.get()
            let lines = text.components(separatedBy: .newlines)
            let trimmed = lines.suffix(maxLines).joined(separator: "\n")
            await MainActor.run {
                fileFallbackContent = trimmed
                lastFileUpdated = Date()
            }
        }
    }
}
