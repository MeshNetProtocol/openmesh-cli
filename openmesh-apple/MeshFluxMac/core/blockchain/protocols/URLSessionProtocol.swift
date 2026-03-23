//
//  URLSessionProtocol.swift
//  MeshFluxMac
//
//  对 URLSession 的最小接口抽象，使 HTTP 依赖可在测试中替换为 Mock。
//  所有需要发起 HTTP 请求的 Service 都应依赖此协议，不直接持有 URLSession。
//

import Foundation

/// HTTP 请求抽象协议。
/// 符合 `Sendable` 以支持 actor 和 async/await 上下文。
protocol URLSessionProtocol: Sendable {

    /// 发起数据请求
    /// - Parameter request: URLRequest
    /// - Returns: (Data, URLResponse) 元组
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession 默认实现

extension URLSession: URLSessionProtocol {}
