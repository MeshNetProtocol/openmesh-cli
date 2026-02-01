//
//  ConnectionModel.swift
//  MeshFluxMac
//
//  单条连接展示模型，与 sing-box ApplicationLibrary/Views/Connections/Connection.swift 对齐。
//

import Foundation
import OpenMeshGo

/// 单条连接（由 OMLibboxConnection 转换而来，用于 UI 展示）
public struct ConnectionModel: Codable, Identifiable, Hashable {
    public let id: String
    public let inbound: String
    public let inboundType: String
    public let ipVersion: Int32
    public let network: String
    public let source: String
    public let destination: String
    public let domain: String
    public let displayDestination: String
    public let protocolName: String
    public let user: String
    public let fromOutbound: String
    public let createdAt: Date
    public let closedAt: Date?
    public var upload: Int64
    public var download: Int64
    public var uploadTotal: Int64
    public var downloadTotal: Int64
    public let rule: String
    public let outbound: String
    public let outboundType: String
    public let chain: [String]

    /// 用于 List 的稳定 identity（id + 流量变化会导致刷新）
    public var listHash: Int {
        var v = id.hashValue
        v = v &+ upload.hashValue
        v = v &+ download.hashValue
        v = v &+ uploadTotal.hashValue
        v = v &+ downloadTotal.hashValue
        return v
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(listHash)
    }
    public static func == (lhs: ConnectionModel, rhs: ConnectionModel) -> Bool {
        lhs.id == rhs.id && lhs.listHash == rhs.listHash
    }

    /// 简单关键词搜索（目标、域名）
    public func matchesSearch(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return true }
        return destination.lowercased().contains(t) || domain.lowercased().contains(t)
    }
}

/// 将 OMLibboxConnection 转为 ConnectionModel；跳过 dns 出站。
public func connectionModels(from goConnections: [OMLibboxConnection]) -> [ConnectionModel] {
    goConnections.compactMap { go -> ConnectionModel? in
        if go.outboundType == "dns" { return nil }
        let closedAt: Date? = go.closedAt > 0 ? Date(timeIntervalSince1970: Double(go.closedAt) / 1000) : nil
        let chainArray: [String] = {
            guard let it = go.chain() else { return [] }
            var arr: [String] = []
            while it.hasNext() {
                arr.append(it.next())
            }
            return arr
        }()
        return ConnectionModel(
            id: go.id_,
            inbound: go.inbound,
            inboundType: go.inboundType,
            ipVersion: go.ipVersion,
            network: go.network,
            source: go.source,
            destination: go.destination,
            domain: go.domain,
            displayDestination: go.displayDestination(),
            protocolName: go.protocol,
            user: go.user,
            fromOutbound: go.fromOutbound,
            createdAt: Date(timeIntervalSince1970: Double(go.createdAt) / 1000),
            closedAt: closedAt,
            upload: go.uplink,
            download: go.downlink,
            uploadTotal: go.uplinkTotal,
            downloadTotal: go.downlinkTotal,
            rule: go.rule,
            outbound: go.outbound,
            outboundType: go.outboundType,
            chain: chainArray
        )
    }
}
