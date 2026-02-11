//
//  LogCommandClient.swift
//  MeshFluxIos
//
//  主 App 通过 extension 的 command.sock 获取实时日志流（与 sing-box LogView / CommandClient(.log) 一致）。
//

import Combine
import Foundation
import OpenMeshGo

/// 仅用于日志的 CommandClient 封装，连接 extension 的 command.sock 获取实时日志。
public final class LogCommandClient: ObservableObject {
    @Published public private(set) var logList: [String] = []
    @Published public private(set) var isConnected: Bool = false

    private let maxLines: Int
    private var commandClient: OMLibboxCommandClient?
    private var connectTask: Task<Void, Error>?

    public init(maxLines: Int = 500) {
        self.maxLines = maxLines
    }

    public func connect() {
        if isConnected || connectTask != nil { return }
        connectTask = Task { [weak self] in
            await self?.connect0()
            await MainActor.run {
                self?.connectTask = nil
            }
        }
    }

    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        try? commandClient?.disconnect()
        commandClient = nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }

    private func connect0() async {
        await LibboxBootstrap.shared.ensureConfigured()

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandLog
        options.statusInterval = 500 * Int64(NSEC_PER_MSEC)

        guard let client = OMLibboxNewCommandClient(LogCommandClientHandler(self), options) else {
            return
        }

        // Extension creates command.sock only after startTunnel; retry with backoff.
        for i in 0 ..< 24 {
            do {
                try await Task.sleep(nanoseconds: UInt64(100 + i * 50) * NSEC_PER_MSEC)
                try Task.checkCancellation()
            } catch {
                _ = try? client.disconnect()
                return
            }
            do {
                try client.connect()
                try Task.checkCancellation()
                await MainActor.run {
                    commandClient = client
                }
                return
            } catch {
                if Task.isCancelled {
                    _ = try? client.disconnect()
                    return
                }
            }
        }
        _ = try? client.disconnect()
    }

    fileprivate func onConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.logList = []
            self?.isConnected = true
        }
    }

    fileprivate func onDisconnected(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.commandClient = nil
            self?.isConnected = false
        }
        if let message {
            NSLog("LogCommandClient disconnected: %@", message)
        }
    }

    fileprivate func onClearLogs() {
        DispatchQueue.main.async { [weak self] in
            self?.logList.removeAll()
        }
    }

    fileprivate func onWriteLogs(_ messageList: OMLibboxStringIteratorProtocol?) {
        guard let messageList else { return }
        var lines: [String] = []
        while messageList.hasNext() {
            lines.append(messageList.next())
        }
        guard !lines.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var newList = self.logList
            newList.append(contentsOf: lines)
            if newList.count > self.maxLines {
                newList.removeFirst(newList.count - self.maxLines)
            }
            self.logList = newList
        }
    }
}

private final class LogCommandClientHandler: NSObject, OMLibboxCommandClientHandlerProtocol {
    private weak var client: LogCommandClient?

    init(_ client: LogCommandClient) {
        self.client = client
    }

    func connected() { client?.onConnected() }
    func disconnected(_ message: String?) { client?.onDisconnected(message) }
    func clearLogs() { client?.onClearLogs() }
    func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) { client?.onWriteLogs(messageList) }

    func writeStatus(_ message: OMLibboxStatusMessage?) {}
    func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {}
    func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ message: OMLibboxConnections?) {}
}
