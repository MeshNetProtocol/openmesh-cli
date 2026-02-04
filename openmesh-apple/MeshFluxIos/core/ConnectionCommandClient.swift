//
//  ConnectionCommandClient.swift
//  MeshFluxIos
//
//  连接 extension 的 command.sock 获取实时连接列表（与 sing-box ConnectionListView 一致）。
//

import Combine
import Foundation
import OpenMeshGo

/// 连接状态筛选：全部 / 仅活动 / 仅已关闭
public enum ConnectionStateFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case active = 1
    case closed = 2

    public var id: Self { self }
    public var name: String {
        switch self {
        case .all: return "全部"
        case .active: return "活动中"
        case .closed: return "已关闭"
        }
    }
}

/// 连接列表排序方式
public enum ConnectionSort: Int, CaseIterable, Identifiable {
    case byDate = 0
    case byTraffic = 1
    case byTrafficTotal = 2

    public var id: Self { self }
    public var name: String {
        switch self {
        case .byDate: return "时间"
        case .byTraffic: return "流量"
        case .byTrafficTotal: return "总流量"
        }
    }
}

/// 连接 extension 的 CommandClient(.connections)，接收连接列表；支持筛选、排序。
public final class ConnectionCommandClient: ObservableObject {
    @Published public private(set) var connections: [OMLibboxConnection]?
    @Published public private(set) var isConnected: Bool = false
    @Published public var connectionStateFilter: ConnectionStateFilter
    @Published public var connectionSort: ConnectionSort

    public var rawConnections: OMLibboxConnections?

    private var commandClient: OMLibboxCommandClient?
    private var connectTask: Task<Void, Error>?
    private var disconnectingByUs: Bool = false
    private let disconnectLock = NSLock()

    public init() {
        self.connectionStateFilter = .active
        self.connectionSort = .byDate
    }

    public func connect() {
        if isConnected { return }
        connectTask?.cancel()
        connectTask = nil
        disconnectLock.withLock { disconnectingByUs = false }
        connectTask = Task { await connect0() }
    }

    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        disconnectLock.withLock { disconnectingByUs = true }
        try? commandClient?.disconnect()
        commandClient = nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connections = nil
            self?.rawConnections = nil
        }
    }

    public func filterConnectionsNow() {
        guard let message = rawConnections else { return }
        message.filterState(Int32(connectionStateFilter.rawValue))
        switch connectionSort {
        case .byDate: message.sortByDate()
        case .byTraffic: message.sortByTraffic()
        case .byTrafficTotal: message.sortByTrafficTotal()
        }
        guard let iter = message.iterator() else {
            DispatchQueue.main.async { [weak self] in self?.connections = [] }
            return
        }
        var list: [OMLibboxConnection] = []
        while iter.hasNext() {
            if let c = iter.next() { list.append(c) }
        }
        DispatchQueue.main.async { [weak self] in
            self?.connections = list
        }
    }

    public func closeConnections() throws {
        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.closeConnections()
    }

    private func connect0() async {
        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandConnections
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(ConnectionCommandClientHandler(self), options) else {
            return
        }

        for i in 0 ..< 24 {
            try? await Task.sleep(nanoseconds: UInt64(100 + i * 50) * NSEC_PER_MSEC)
            try? Task.checkCancellation()
            do {
                try client.connect()
                await MainActor.run {
                    commandClient = client
                }
                return
            } catch {
                try? Task.checkCancellation()
            }
        }
        try? client.disconnect()
    }

    fileprivate func onConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
        }
    }

    fileprivate func onDisconnected(_ message: String?) {
        let wasByUs = disconnectLock.withLock {
            let v = disconnectingByUs
            disconnectingByUs = false
            return v
        }
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connections = nil
            self?.rawConnections = nil
        }
        if !wasByUs, let message { NSLog("ConnectionCommandClient disconnected: %@", message) }
    }

    fileprivate func onWriteConnections(_ message: OMLibboxConnections?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rawConnections = message
            self.filterConnectionsNow()
        }
    }
}

private final class ConnectionCommandClientHandler: NSObject, OMLibboxCommandClientHandlerProtocol {
    private weak var client: ConnectionCommandClient?

    init(_ client: ConnectionCommandClient) {
        self.client = client
    }

    func connected() { client?.onConnected() }
    func disconnected(_ message: String?) { client?.onDisconnected(message) }
    func clearLogs() {}
    func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) {}
    func writeStatus(_ message: OMLibboxStatusMessage?) {}
    func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {}
    func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ message: OMLibboxConnections?) { client?.onWriteConnections(message) }
}
