//
//  BlockchainRPCClientProtocol.swift
//  MeshFluxMac
//
//  定义区块链 JSON-RPC 客户端对外暴露的能力接口。
//  所有调用方只依赖此协议，不依赖具体实现类，以便在测试中替换为 Mock。
//

import Foundation

/// 区块链 JSON-RPC 客户端协议。
/// 覆盖 V2 所需的最小链上只读调用集合。
protocol BlockchainRPCClientProtocol: Sendable {

    /// 调用合约只读函数（eth_call）
    /// - Parameters:
    ///   - to: 合约地址（0x 开头）
    ///   - data: ABI 编码的调用 data（0x 开头）
    /// - Returns: 响应的 result 字段（hex 字符串）
    func ethCall(to: String, data: String) async throws -> String

    /// 查询事件日志（eth_getLogs）
    /// - Parameters:
    ///   - address: 合约地址
    ///   - topics: 过滤 topics 数组（nil 表示不过滤）
    ///   - fromBlock: 起始区块（"earliest" / "latest" / 十六进制）
    ///   - toBlock: 结束区块（"latest" 等）
    /// - Returns: 日志对象数组（原始 JSON 字典）
    func ethGetLogs(
        address: String,
        topics: [[String]]?,
        fromBlock: String,
        toBlock: String
    ) async throws -> [[String: Any]]

    /// 查询 ERC-20 代币余额（eth_call 封装）
    /// - Parameters:
    ///   - tokenAddress: 代币合约地址
    ///   - ownerAddress: 持有人地址
    /// - Returns: 余额（原始 uint256 整数字符串，最小单位）
    func erc20BalanceOf(tokenAddress: String, ownerAddress: String) async throws -> String
}
