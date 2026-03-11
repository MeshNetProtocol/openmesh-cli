//
//  BlockchainError.swift
//  MeshFluxMac
//
//  V2 区块链模块统一错误枚举。
//  所有 RPC、ABI、钱包、签名、支付和安装阶段的错误都应映射到此枚举，
//  以便上层 Store / ViewModel 能统一处理并向用户展示可理解的错误信息。
//

import Foundation

enum BlockchainError: Error, LocalizedError {

    // MARK: - RPC / 网络层

    /// HTTP 请求失败（包含底层 URLError）
    case networkError(Error)
    /// HTTP 响应状态码非 200
    case httpError(statusCode: Int)
    /// 响应体不是合法 JSON
    case invalidJSON
    /// RPC 返回了 JSON-RPC error 字段
    case rpcError(code: Int, message: String)
    /// 响应结构与预期不符（缺少 result 字段等）
    case unexpectedResponse

    // MARK: - ABI / 合约层

    /// ABI 编码失败
    case abiEncodingFailed
    /// ABI 解码失败（返回数据长度或格式不对）
    case abiDecodingFailed
    /// 合约地址未配置（部署前占位）
    case contractAddressNotConfigured

    // MARK: - 钱包层

    /// Keychain 保存失败
    case keychainSaveFailed(OSStatus)
    /// Keychain 读取失败（或项目不存在）
    case keychainReadFailed(OSStatus)
    /// 私钥加密失败
    case encryptionFailed
    /// 私钥解密失败（通常是密码错误）
    case decryptionFailed
    /// 解锁方式不受当前设备支持
    case biometricsNotAvailable
    /// 生物识别验证失败
    case biometricsFailed
    /// 钱包不存在（未创建也未恢复）
    case walletNotFound
    /// 钱包处于锁定状态，需要先解锁
    case walletLocked
    /// 助记词无效（词数不对或校验失败）
    case invalidMnemonic
    /// HD 派生失败
    case keyDerivationFailed

    // MARK: - 供应商层

    /// 供应商列表为空
    case supplierListEmpty
    /// 单个供应商 metadata 拉取失败
    case metadataFetchFailed(supplierID: String)
    /// metadata JSON 格式非法
    case metadataInvalid(supplierID: String)
    /// 供应商已过期或被暂停
    case supplierInactive(supplierID: String)
    /// configURLs 为空或全部非法
    case noValidConfigURL

    // MARK: - x402 支付层

    /// 余额不足
    case insufficientBalance(required: String, available: String)
    /// EIP-712 签名失败
    case signingFailed
    /// Authorization 时间窗口已过期
    case x402SignatureExpired
    /// nonce 生成失败
    case nonceFailed
    /// 服务端返回 402 且重试次数耗尽
    case x402MaxRetriesExceeded
    /// 配置下载失败（非 402 错误）
    case configDownloadFailed(statusCode: Int)

    // MARK: - 安装层

    /// 配置数据为空
    case emptyConfigData
    /// 安装接入点失败
    case installationFailed(underlying: Error)

    // MARK: - 通用

    /// 未知错误（兜底）
    case unknown(Error)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .networkError:           return "网络请求失败，请检查网络连接"
        case .httpError(let code):    return "请求失败（HTTP \(code)）"
        case .invalidJSON:            return "服务器返回格式错误"
        case .rpcError(_, let msg):   return "链上服务错误：\(msg)"
        case .unexpectedResponse:     return "响应结构异常"
        case .abiEncodingFailed:      return "合约参数编码失败"
        case .abiDecodingFailed:      return "合约返回解析失败"
        case .contractAddressNotConfigured: return "合约地址未配置"
        case .keychainSaveFailed:     return "账户保存失败，请重试"
        case .keychainReadFailed:     return "账户读取失败，请重试"
        case .encryptionFailed:       return "账户加密失败"
        case .decryptionFailed:       return "密码错误，解锁失败"
        case .biometricsNotAvailable: return "当前设备不支持生物识别"
        case .biometricsFailed:       return "生物识别验证失败"
        case .walletNotFound:         return "未找到金豆账户"
        case .walletLocked:           return "账户已锁定，请先解锁"
        case .invalidMnemonic:        return "恢复短语无效，请检查后重试"
        case .keyDerivationFailed:    return "账户恢复失败"
        case .supplierListEmpty:      return "暂无可用供应商"
        case .metadataFetchFailed:    return "供应商信息读取失败"
        case .metadataInvalid:        return "供应商信息格式异常"
        case .supplierInactive:       return "该供应商当前不可用"
        case .noValidConfigURL:       return "供应商配置地址无效"
        case .insufficientBalance:    return "金豆余额不足，请先充值"
        case .signingFailed:          return "支付授权失败"
        case .x402SignatureExpired:   return "支付授权已过期，请重试"
        case .nonceFailed:            return "支付参数生成失败"
        case .x402MaxRetriesExceeded: return "配置获取失败，请稍后重试"
        case .configDownloadFailed(let code): return "配置下载失败（\(code)），请稍后重试"
        case .emptyConfigData:        return "配置内容为空"
        case .installationFailed:     return "安装失败，请重试"
        case .unknown:                return "发生未知错误，请重试"
        }
    }
}
