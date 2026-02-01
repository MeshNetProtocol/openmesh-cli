//
//  StatusCommandClient.swift
//  MeshFluxMac
//
//  连接 extension 的 command.sock 获取实时状态（内存、协程数、连接数、流量），与 sing-box ExtensionStatusView / CommandClient(.status) 一致。
//

import Combine
import Foundation
import OpenMeshGo
import VPNLibrary

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
            self?.status = nil
        }
    }

    private func connect0() async {
        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandStatus
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(StatusCommandClientHandler(self), options) else {
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
            self?.status = nil
        }
        if !wasByUs, let message { NSLog("StatusCommandClient disconnected: %@", message) }
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
