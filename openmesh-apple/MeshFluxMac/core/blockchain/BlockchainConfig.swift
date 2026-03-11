//
//  BlockchainConfig.swift
//  MeshFluxMac
//
//  V2 区块链配置中心。
//  所有链上常量（RPC URL、合约地址、代币地址、网络标识）统一在此管理。
//  切换测试网只需修改 useTestnet 标志。
//

import Foundation

enum BlockchainConfig {

    // MARK: - 网络切换

    /// 是否使用测试网。生产版本必须保持 false。
    static let useTestnet: Bool = false

    // MARK: - RPC 节点

    static let mainnetRPCURL = "https://mainnet.base.org"
    static let testnetRPCURL = "https://sepolia.base.org"

    static var rpcURL: String {
        useTestnet ? testnetRPCURL : mainnetRPCURL
    }

    // MARK: - USDC 合约地址

    /// Base Mainnet USDC
    static let mainnetUSDCAddress = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    /// Base Sepolia USDC
    static let testnetUSDCAddress = "0x036CbD53842c5426634e7929541eC2318f3dCF7e"

    static var usdcAddress: String {
        useTestnet ? testnetUSDCAddress : mainnetUSDCAddress
    }

    // MARK: - 协议注册合约地址（供应商目录来源）

    /// 合约部署完成后填入。占位值为空字符串。
    static let mainnetRegistryAddress = ""
    static let testnetRegistryAddress = ""

    static var registryAddress: String {
        useTestnet ? testnetRegistryAddress : mainnetRegistryAddress
    }

    // MARK: - 网络名称（用于 x402 Authorization header）

    static var networkName: String {
        useTestnet ? "base-sepolia" : "base-mainnet"
    }

    // MARK: - Chain ID

    static let mainnetChainID: Int = 8453
    static let testnetChainID: Int = 84532

    static var chainID: Int {
        useTestnet ? testnetChainID : mainnetChainID
    }
}
