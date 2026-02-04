//
//  OpenmeshAppLibStub.swift
//  MeshFluxIos
//
//  与 Go go-cli-lib 接口对应的 Swift 类型与协议；真实实现由 OpenmeshAppLibBridge 调用 OMOpenmeshNewLib()。
//  OMOpenmeshNewLib() 失败时 GoEngine 直接报错，不再使用桩逻辑。
//

import Foundation

// MARK: - Wallet & VPN types (mirror Go go-cli-lib interface)

struct WalletSecretsV1 {
    var v: Int
    var privateKeyHex: String
    var address: String
}

struct VpnStatus {
    var connected: Bool
    var server: String
    var bytesIn: Int64
    var bytesOut: Int64
}

// MARK: - AppLib protocol (used by GoEngine; implemented by OpenmeshAppLibBridge)

protocol OpenmeshAppLibProtocol: AnyObject {
    func initApp(_ config: Data) throws
    func generateMnemonic12() throws -> String
    func createEvmWallet(_ mnemonic: String, password: String) throws -> String
    func decryptEvmWallet(_ keystoreJSON: String, password: String) throws -> WalletSecretsV1
    func getTokenBalance(_ address: String, tokenName: String, networkName: String) throws -> String
    func getSupportedNetworks() throws -> String
    func getVpnStatus() -> VpnStatus?
}
