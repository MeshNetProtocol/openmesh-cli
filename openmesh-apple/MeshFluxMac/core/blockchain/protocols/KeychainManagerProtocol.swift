//
//  KeychainManagerProtocol.swift
//  MeshFluxMac
//
//  定义 Keychain 安全存储管理器的对外接口。
//  所有钱包敏感数据（加密私钥、salt、身份对象）的读写都经由此协议，
//  以便在测试中替换为 MockKeychainManager，避免污染系统真实 Keychain。
//

import Foundation

/// Keychain 安全存储协议。
/// 覆盖 V2 钱包所需的最小敏感数据读写集合。
protocol KeychainManagerProtocol: Sendable {

    // MARK: - 加密私钥

    /// 保存加密后的私钥密文
    func saveEncryptedPrivateKey(_ data: Data) throws

    /// 读取加密后的私钥密文
    func loadEncryptedPrivateKey() throws -> Data

    // MARK: - Salt

    /// 保存 KDF 使用的随机 salt
    func saveSalt(_ data: Data) throws

    /// 读取 salt
    func loadSalt() throws -> Data

    // MARK: - 钱包身份

    /// 保存钱包身份对象（地址 + 创建时间 + 解锁方式）
    func saveWalletIdentity(_ data: Data) throws

    /// 读取钱包身份对象
    func loadWalletIdentity() throws -> Data

    // MARK: - 状态检查

    /// 判断是否已存在钱包（通过检查加密私钥项是否存在）
    func walletExists() -> Bool

    // MARK: - 清除

    /// 删除所有钱包相关 Keychain 项（用于账户重置或恢复覆盖前）
    func deleteAll() throws
}
