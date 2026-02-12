//
//  OpenmeshAppLibBridge.swift
//  MeshFluxIos
//
//  封装 OpenMeshGo 的 OMOpenmeshAppLib，实现 OpenmeshAppLibProtocol，
//  将 Go 返回的类型转换为 App 内使用的 WalletSecretsV1 / VpnStatus。
//

import Foundation
import OpenMeshGo

final class OpenmeshAppLibBridge: OpenmeshAppLibProtocol {
    private let omLib: OMOpenmeshAppLib

    init(omLib: OMOpenmeshAppLib) {
        self.omLib = omLib
    }

    func initApp(_ config: Data) throws {
        try omLib.initApp(config)
    }

    func generateMnemonic12() throws -> String {
        var err: NSError?
        let s = omLib.generateMnemonic12(&err)
        if let e = err { throw e }
        return s
    }

    func createEvmWallet(_ mnemonic: String, password: String) throws -> String {
        var err: NSError?
        let json = omLib.createEvmWallet(mnemonic, password: password, error: &err)
        if let e = err { throw e }
        return json
    }

    func decryptEvmWallet(_ keystoreJSON: String, password: String) throws -> WalletSecretsV1 {
        let om = try omLib.decryptEvmWallet(keystoreJSON, password: password)
        return WalletSecretsV1(
            v: Int(om.v),
            privateKeyHex: om.privateKeyHex,
            address: om.address
        )
    }

    func getTokenBalance(_ address: String, tokenName: String, networkName: String) throws -> String {
        let threadDesc = Thread.isMainThread ? "main" : "background"
        NSLog(
            "OpenmeshAppLibBridge.getTokenBalance start thread=%@ address=%@ token=%@ network=%@",
            threadDesc,
            address,
            tokenName,
            networkName
        )
        var err: NSError?
        let balance = omLib.getTokenBalance(address, tokenName: tokenName, networkName: networkName, error: &err)
        if let e = err {
            NSLog("OpenmeshAppLibBridge.getTokenBalance failed thread=%@ error=%@", threadDesc, String(describing: e))
            throw e
        }
        NSLog("OpenmeshAppLibBridge.getTokenBalance success thread=%@ balance=%@", threadDesc, balance)
        return balance
    }

    func getSupportedNetworks() throws -> String {
        var err: NSError?
        let json = omLib.getSupportedNetworks(&err)
        if let e = err { throw e }
        return json
    }

    func getVpnStatus() -> VpnStatus? {
        guard let om = omLib.getVpnStatus() else { return nil }
        NSLog("OpenmeshAppLibBridge.getVpnStatus connected=%@ server=%@", om.connected.description, om.server)
        return VpnStatus(
            connected: om.connected,
            server: om.server,
            bytesIn: om.bytesIn,
            bytesOut: om.bytesOut
        )
    }
}
