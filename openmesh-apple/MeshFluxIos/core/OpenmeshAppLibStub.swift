//
//  OpenmeshAppLibStub.swift
//  MeshFluxIos
//
//  Swift-only types and stub for the Go openmesh AppLib API when the go-cli-lib
//  framework is not built into OpenMeshGo (OpenMeshGo is built from sing-box libbox only).
//  Replace with real OMOpenmeshAppLib / OMOpenmeshNewLib / OMOpenmeshWalletSecretsV1
//  when a separate xcframework is built from go-cli-lib.
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

// MARK: - AppLib protocol (matches Go AppLib surface used by GoEngine + HomeTabView)

protocol OpenmeshAppLibProtocol: AnyObject {
    func initApp(_ config: Data) throws
    func generateMnemonic12() throws -> String
    func createEvmWallet(_ mnemonic: String, password: String) throws -> String
    func decryptEvmWallet(_ keystoreJSON: String, password: String) throws -> WalletSecretsV1
    func getTokenBalance(_ address: String, tokenName: String, networkName: String) throws -> String
    func getSupportedNetworks() throws -> String
    func getVpnStatus() -> VpnStatus?
}

// MARK: - Stub implementation (used until go-cli-lib is built as a framework)

final class StubAppLib: OpenmeshAppLibProtocol {
    func initApp(_ config: Data) throws {
        // no-op
    }

    func generateMnemonic12() throws -> String {
        throw GoEngineError.notReadyYet
    }

    func createEvmWallet(_ mnemonic: String, password: String) throws -> String {
        throw GoEngineError.notReadyYet
    }

    func decryptEvmWallet(_ keystoreJSON: String, password: String) throws -> WalletSecretsV1 {
        throw GoEngineError.notReadyYet
    }

    func getTokenBalance(_ address: String, tokenName: String, networkName: String) throws -> String {
        throw GoEngineError.notReadyYet
    }

    func getSupportedNetworks() throws -> String {
        throw GoEngineError.notReadyYet
    }

    func getVpnStatus() -> VpnStatus? {
        return VpnStatus(connected: false, server: "", bytesIn: 0, bytesOut: 0)
    }
}
