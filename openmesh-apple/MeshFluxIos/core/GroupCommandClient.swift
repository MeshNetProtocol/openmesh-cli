//
//  GroupCommandClient.swift
//  MeshFluxIos
//
//  主 App 通过 extension 的 command.sock 获取出站组列表（与 sing-box GroupListView / CommandClient(.groups) 一致）。
//  仅当 VPN 已连接时可用；用于展示出站组并触发 URL 测速、切换节点。
//

import Combine
import Foundation
@preconcurrency import OpenMeshGo
import VPNLibrary

private final class UncheckedSendableCommandClient: @unchecked Sendable {
    let client: OMLibboxCommandClient
    init(_ client: OMLibboxCommandClient) {
        self.client = client
    }
}

/// 出站组单项（tag、类型、测速延迟等），与 sing-box OutboundGroupItem 对齐。
public struct OutboundGroupItemModel: Identifiable {
    public let tag: String
    public let type: String
    public let urlTestTime: Date
    public let urlTestDelay: UInt16

    public var id: String { tag }

    public var delayString: String { "\(urlTestDelay)ms" }

    public var delayColor: (r: Double, g: Double, b: Double) {
        switch urlTestDelay {
        case 0: return (0.5, 0.5, 0.5)
        case ..<800: return (0, 0.8, 0)
        case 800 ..< 1500: return (0.9, 0.8, 0)
        default: return (1, 0.6, 0)
        }
    }
}

/// 出站组（selector/urltest 等），与 sing-box OutboundGroup 对齐。
public struct OutboundGroupModel: Identifiable {
    public let tag: String
    public let type: String
    public var selected: String
    public let selectable: Bool
    public var isExpand: Bool
    public let items: [OutboundGroupItemModel]

    public var id: String { tag }
}

/// 连接 extension 的 CommandClient(.groups)，接收出站组列表。
public final class GroupCommandClient: ObservableObject {
    @Published public private(set) var groups: [OutboundGroupModel] = []
    @Published public private(set) var isConnected: Bool = false

    private var commandClient: OMLibboxCommandClient?
    private var connectTask: Task<Void, Error>?
    private var disconnectingByUs: Bool = false
    private let disconnectLock = NSLock()
    private let commandSendQueue = DispatchQueue(label: "meshflux.command.send")

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
            self?.groups = []
        }
    }

    /// 对指定出站组执行 URL 测速。
    public func urlTest(groupTag: String) async throws {
        let group = stableInput(groupTag)
        guard validateTag(group) else {
            throw NSError(domain: "com.meshflux", code: 1001, userInfo: [NSLocalizedDescriptionKey: "非法 groupTag"])
        }

        let connectedClient = await MainActor.run { self.commandClient }
        if let connectedClient {
            let clientRef = UncheckedSendableCommandClient(connectedClient)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                commandSendQueue.async {
                    do {
                        try clientRef.client.urlTest(group)
                        cont.resume(returning: ())
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            return
        }

        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.urlTest(group)
    }

    /// 切换出站组当前选中的节点。仅对 selector 类型有效。
    public func selectOutbound(groupTag: String, outboundTag: String) async throws {
        let group = stableInput(groupTag)
        let outbound = stableInput(outboundTag)
        guard validateTag(group), validateTag(outbound) else {
            throw NSError(domain: "com.meshflux", code: 1003, userInfo: [NSLocalizedDescriptionKey: "非法 outboundTag"])
        }

        let connectedClient = await MainActor.run { self.commandClient }
        if let connectedClient {
            let clientRef = UncheckedSendableCommandClient(connectedClient)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                commandSendQueue.async {
                    do {
                        try clientRef.client.selectOutbound(group, outboundTag: outbound)
                        cont.resume(returning: ())
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            return
        }

        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.selectOutbound(group, outboundTag: outbound)
    }

    /// 设置出站组展开/收起（同步到 extension，并更新本地缓存）。
    public func setGroupExpand(groupTag: String, isExpand: Bool) async throws {
        let group = stableInput(groupTag)
        guard validateTag(group) else {
            throw NSError(domain: "com.meshflux", code: 1004, userInfo: [NSLocalizedDescriptionKey: "非法 groupTag"])
        }

        let connectedClient = await MainActor.run { self.commandClient }
        if let connectedClient {
            let clientRef = UncheckedSendableCommandClient(connectedClient)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                commandSendQueue.async {
                    do {
                        try clientRef.client.setGroupExpand(group, isExpand: isExpand)
                        cont.resume(returning: ())
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            setExpand(groupTag: group, isExpand: isExpand)
            return
        }

        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.setGroupExpand(group, isExpand: isExpand)
        setExpand(groupTag: group, isExpand: isExpand)
    }

    /// 更新本地缓存的出站组选中项（用于点击节点后立即刷新 UI）。
    public func setSelected(groupTag: String, outboundTag: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = self.groups.firstIndex(where: { $0.tag == groupTag }) else { return }
            var list = self.groups
            list[idx].selected = outboundTag
            self.groups = list
        }
    }

    /// 更新本地缓存的出站组展开状态（用于点击展开/收起后立即刷新 UI）。
    public func setExpand(groupTag: String, isExpand: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = self.groups.firstIndex(where: { $0.tag == groupTag }) else { return }
            var list = self.groups
            list[idx].isExpand = isExpand
            self.groups = list
        }
    }

    private func connect0() async {
        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandGroup
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(GroupCommandClientHandler(self), options) else {
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
        _ = try? client.disconnect()
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
            self?.groups = []
        }
        if !wasByUs, let message { NSLog("GroupCommandClient disconnected: %@", message) }
    }

    fileprivate func onWriteGroups(_ groupsIterator: OMLibboxOutboundGroupIteratorProtocol?) {
        guard let groupsIterator else { return }
        func stable(_ s: String) -> String { stableInput(s) }
        var list: [OutboundGroupModel] = []
        while groupsIterator.hasNext() {
            guard let goGroup = groupsIterator.next() else { break }
            var items: [OutboundGroupItemModel] = []
            if let itemIter = goGroup.getItems() {
                while itemIter.hasNext() {
                    guard let goItem = itemIter.next() else { break }
                    items.append(OutboundGroupItemModel(
                        tag: stable(goItem.tag),
                        type: stable(goItem.type),
                        urlTestTime: Date(timeIntervalSince1970: Double(goItem.urlTestTime)),
                        urlTestDelay: UInt16(goItem.urlTestDelay)
                    ))
                }
            }
            list.append(OutboundGroupModel(
                tag: stable(goGroup.tag),
                type: stable(goGroup.type),
                selected: stable(goGroup.selected),
                selectable: goGroup.selectable,
                isExpand: goGroup.isExpand,
                items: items
            ))
        }
        DispatchQueue.main.async { [weak self] in
            self?.groups = list
        }
    }

    private func stableInput(_ s: String) -> String {
        // Force a deep copy immediately, avoiding any sharing with transient buffers.
        String(decoding: Array(s.utf8), as: UTF8.self)
    }

    private func validateTag(_ s: String) -> Bool {
        // Conservative: we only accept typical ASCII tags here to avoid feeding corrupted memory into native lib.
        if s.isEmpty || s.count > 128 { return false }
        if s.utf8.contains(0) { return false }
        return s.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return v >= 0x20 && v < 0x7f
        }
    }
}

private final class GroupCommandClientHandler: NSObject, OMLibboxCommandClientHandlerProtocol {
    private weak var client: GroupCommandClient?

    init(_ client: GroupCommandClient) {
        self.client = client
    }

    func connected() { client?.onConnected() }
    func disconnected(_ message: String?) { client?.onDisconnected(message) }
    func clearLogs() {}
    func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) {}
    func writeStatus(_ message: OMLibboxStatusMessage?) {}
    func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) { client?.onWriteGroups(groups) }
    func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ message: OMLibboxConnections?) {}
}
