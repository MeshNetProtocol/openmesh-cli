//
//  GroupCommandClient.swift
//  MeshFluxMac
//
//  主 App 通过 extension 的 command.sock 获取出站组列表（与 sing-box GroupListView / CommandClient(.groups) 一致）。
//  仅当 VPN 已连接时可用；用于展示出站组并触发 URL 测速。
//

import Combine
import Foundation
import OpenMeshGo
import VPNLibrary

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
/// 与 sing-box 对齐：参考 `openmesh-cli/sing-box/clients/apple/ApplicationLibrary/Views/Groups/GroupListView.swift`、
/// `sing-box/clients/apple/Library/Network/CommandClient.swift`。
public final class GroupCommandClient: ObservableObject {
    @Published public private(set) var groups: [OutboundGroupModel] = []
    @Published public private(set) var isConnected: Bool = false

    private var commandClient: OMLibboxCommandClient?
    private var connectTask: Task<Void, Error>?
    /// 由我们主动 disconnect 时置为 true，onDisconnected 回调时不打“错误”日志。读写需在 lock 内（回调可能在不同线程）。
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
            self?.groups = []
        }
    }

    /// 对指定出站组执行 URL 测速（与 sing-box GroupView doURLTest 一致）。使用 StandaloneCommandClient 一次性连接发送命令。
    public func urlTest(groupTag: String) async throws {
        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.urlTest(groupTag)
    }

    /// 切换出站组当前选中的节点（与 sing-box GroupItemView selectOutbound 一致）。仅对 selector 类型有效。
    public func selectOutbound(groupTag: String, outboundTag: String) async throws {
        guard let client = OMLibboxNewStandaloneCommandClient() else {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewStandaloneCommandClient 返回 nil"])
        }
        try client.selectOutbound(groupTag, outboundTag: outboundTag)
    }

    /// 更新本地缓存的出站组选中项（用于点击节点后立即刷新 UI，与 extension 下发的 writeGroups 一致）。
    public func setSelected(groupTag: String, outboundTag: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = self.groups.firstIndex(where: { $0.tag == groupTag }) else { return }
            var list = self.groups
            list[idx].selected = outboundTag
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
        // 由我们主动 disconnect（如切换 tab）时不要当错误打印，避免误导
        if !wasByUs, let message { NSLog("GroupCommandClient disconnected: %@", message) }
    }

    fileprivate func onWriteGroups(_ groupsIterator: OMLibboxOutboundGroupIteratorProtocol?) {
        guard let groupsIterator else { return }
        var list: [OutboundGroupModel] = []
        while groupsIterator.hasNext() {
            guard let goGroup = groupsIterator.next() else { break }
            var items: [OutboundGroupItemModel] = []
            if let itemIter = goGroup.getItems() {
                while itemIter.hasNext() {
                    guard let goItem = itemIter.next() else { break }
                    items.append(OutboundGroupItemModel(
                        tag: goItem.tag,
                        type: goItem.type,
                        urlTestTime: Date(timeIntervalSince1970: Double(goItem.urlTestTime)),
                        urlTestDelay: UInt16(goItem.urlTestDelay)
                    ))
                }
            }
            list.append(OutboundGroupModel(
                tag: goGroup.tag,
                type: goGroup.type,
                selected: goGroup.selected,
                selectable: goGroup.selectable,
                isExpand: goGroup.isExpand,
                items: items
            ))
        }
        DispatchQueue.main.async { [weak self] in
            self?.groups = list
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
