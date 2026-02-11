//
//  StatusCommandClient.swift
//  MeshFluxIos
//
//  连接 extension 的 command.sock 获取实时状态（连接数、流量）。仅展示连接数与流量，不展示内存/协程。
//

import Combine
import Foundation
import OpenMeshGo

/// 连接 extension 的 CommandClient(.status)，接收 OMLibboxStatusMessage。
public final class StatusCommandClient: ObservableObject {
    @Published public private(set) var status: OMLibboxStatusMessage?
    @Published public private(set) var isConnected: Bool = false

    private var commandClient: OMLibboxCommandClient?
    private var connectTask: Task<Void, Error>?
    private var disconnectingByUs: Bool = false
    private let disconnectLock = NSLock()

    public init() {}

    public func connect() {
        if isConnected || connectTask != nil { return }
        disconnectLock.withLock { disconnectingByUs = false }
        connectTask = Task { [weak self] in
            await self?.connect0()
            await MainActor.run {
                self?.connectTask = nil
            }
        }
    }

    public func reconnect() {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.connect()
        }
    }

    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        disconnectLock.withLock { disconnectingByUs = true }
        NSLog("StatusCommandClient disconnect requested by app")
        try? commandClient?.disconnect()
        commandClient = nil
        let clear: () -> Void = { [weak self] in
            self?.isConnected = false
            self?.status = nil
        }
        if Thread.isMainThread {
            clear()
        } else {
            DispatchQueue.main.async(execute: clear)
        }
    }

    private func connect0() async {
        await LibboxBootstrap.shared.ensureConfigured()

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandStatus
        options.statusInterval = 2 * Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(StatusCommandClientHandler(self), options) else {
            NSLog("StatusCommandClient connect failed: OMLibboxNewCommandClient returned nil")
            return
        }

        var lastError: Error?
        for i in 0 ..< 24 {
            do {
                try await Task.sleep(nanoseconds: UInt64(100 + i * 50) * NSEC_PER_MSEC)
                try Task.checkCancellation()
            } catch {
                try? client.disconnect()
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
                    try? client.disconnect()
                    return
                }
                lastError = error
            }
        }
        if let lastError {
            NSLog("StatusCommandClient connect failed after retries: %@", String(describing: lastError))
        }
        try? client.disconnect()
    }

    fileprivate func onConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
        }
        NSLog("StatusCommandClient connected")
    }

    fileprivate func onDisconnected(_ message: String?) {
        let wasByUs = disconnectLock.withLock {
            let v = disconnectingByUs
            disconnectingByUs = false
            return v
        }
        DispatchQueue.main.async { [weak self] in
            self?.commandClient = nil
            self?.isConnected = false
            self?.status = nil
        }
        if wasByUs {
            NSLog("StatusCommandClient disconnected by app request")
        } else if let message {
            NSLog("StatusCommandClient disconnected: %@", message)
        }
    }

    fileprivate func onWriteStatus(_ message: OMLibboxStatusMessage?) {
        DispatchQueue.main.async { [weak self] in
            self?.status = message
        }
    }
}

private final class StatusCommandClientHandler: NSObject, OMLibboxCommandClientHandlerProtocol {
    private weak var client: StatusCommandClient?

    init(_ client: StatusCommandClient) {
        self.client = client
    }

    func connected() { client?.onConnected() }
    func disconnected(_ message: String?) { client?.onDisconnected(message) }
    func clearLogs() {}
    func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) {}
    func writeStatus(_ message: OMLibboxStatusMessage?) { client?.onWriteStatus(message) }
    func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {}
    func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ message: OMLibboxConnections?) {}
}
