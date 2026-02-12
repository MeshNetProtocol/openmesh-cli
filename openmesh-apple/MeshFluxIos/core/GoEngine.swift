import Foundation
import OpenMeshGo

enum GoEngineError: LocalizedError {
        /// 核心库（OpenMeshGo）加载失败，无法使用钱包与 VPN 能力。
        case newLibReturnedNil
        
        var errorDescription: String? {
                switch self {
                case .newLibReturnedNil:
                        return "无法加载核心库，请重新安装应用或联系支持。"
                }
        }
}

final class GoEngine {
        static let shared = GoEngine()
        
        private let queue = DispatchQueue(label: "meshflux.go.engine.serial")
        
        private var lib: (any OpenmeshAppLibProtocol)?
        private var cachedConfig: Data = Data()
        
        private var initTask: Task<Void, Error>?

        private func maskAddress(_ address: String) -> String {
                let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.count > 12 else { return t }
                return "\(t.prefix(6))...\(t.suffix(4))"
        }

        private func log(_ message: String) {
                NSLog("GoEngine: %@", message)
        }
        
        /// 懒初始化：不在 init() 中创建 initTask，避免启动时阻塞导致 watchdog 超时
        private init() {
                self.cachedConfig = Data()
                // 不再在 init 中启动初始化任务
                // initTask 将在第一次调用 ensureReady() 时惰性创建
        }
        
        func generateMnemonic12() async throws -> String {
                try await ensureReady()
                
                return try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        let s = try lib.generateMnemonic12()
                                        cont.resume(returning: s)
                                } catch {
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
        
        /// ✅ 新增：调用 Go 的 CreateEvmWallet(mnemonic, pin) -> JSON string
        func createEvmWallet(mnemonic: String, pin: String) async throws -> String {
                try await ensureReady()
                
                return try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        let json = try lib.createEvmWallet(mnemonic, password: pin)
                                        cont.resume(returning: json)
                                } catch {
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
        
        /// ✅ 新增：调用 Go 的 DecryptEvmWallet(keystoreJSON, pin) -> WalletSecretsV1
        func decryptEvmWallet(keystoreJSON: String, pin: String) async throws -> WalletSecretsV1 {
                try await ensureReady()
                
                return try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        let secrets = try lib.decryptEvmWallet(keystoreJSON, password: pin)
                                        cont.resume(returning: secrets)
                                } catch {
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
        
        /// ✅ 新增：调用 Go 的 GetTokenBalance(address, tokenName, networkName) -> balance string
        func getTokenBalance(address: String, tokenName: String, networkName: String) async throws -> String {
                let requestID = UUID().uuidString.lowercased()
                log("getTokenBalance start request_id=\(requestID) address=\(maskAddress(address)) token=\(tokenName) network=\(networkName)")
                try await ensureReady()
                
                return try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        self.log("getTokenBalance invoking Go bridge request_id=\(requestID)")
                                        let balance = try lib.getTokenBalance(address, tokenName: tokenName, networkName: networkName)
                                        self.log("getTokenBalance success request_id=\(requestID) balance=\(balance)")
                                        cont.resume(returning: balance)
                                } catch {
                                        self.log("getTokenBalance failed request_id=\(requestID) error=\(String(describing: error))")
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
        
        /// ✅ 新增：调用 Go 的 GetSupportedNetworks() -> JSON string
        func getSupportedNetworks() async throws -> [String] {
                try await ensureReady()
                
                return try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        let networksJSON = try lib.getSupportedNetworks()
                                        guard let data = networksJSON.data(using: .utf8) else {
                                                throw NSError(domain: "GoEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "支持网络数据无效"])
                                        }
                                        
                                        let networks = try JSONDecoder().decode([String].self, from: data)
                                        cont.resume(returning: networks)
                                } catch {
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
        
        func reconfigure(config: Data) async throws {
                try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                self.cachedConfig = config
                                self.initTask = Task { [weak self] in
                                        guard let self else { return }
                                        try await self.initLocked(config: config)
                                }
                                cont.resume()
                        }
                }
                
                try await ensureReady()
        }
        
        func reset() async {
                await withCheckedContinuation { cont in
                        queue.async {
                                self.lib = nil
                                self.cachedConfig = Data()
                                self.initTask = nil
                                cont.resume()
                        }
                }
        }

        /// 仅释放 Go runtime 对象，保留已缓存配置，供前台快速恢复。
        /// 用于 iOS 退到后台后的内存回收，避免影响后续 Go 交互路径。
        func releaseRuntimeForMemoryPressure() async {
                log("releaseRuntimeForMemoryPressure begin")
                await withCheckedContinuation { cont in
                        queue.async {
                                self.lib = nil
                                self.initTask = nil
                                cont.resume()
                        }
                }
                log("releaseRuntimeForMemoryPressure end")
        }
        
        // MARK: - Internal
        private func ensureReady() async throws {
                if initTask == nil {
                        initTask = Task { [weak self] in
                                guard let self else { return }
                                try await self.initLocked(config: self.cachedConfig)
                        }
                }
                try await initTask?.value
        }
        
        private func initLocked(config: Data) async throws {
                try await withCheckedThrowingContinuation { cont in
                        queue.async {
                                do {
                                        self.cachedConfig = config
                                        
                                        if self.lib == nil {
                                                guard let real = OMOpenmeshNewLib() else {
                                                        throw GoEngineError.newLibReturnedNil
                                                }
                                                self.lib = OpenmeshAppLibBridge(omLib: real)
                                        }
                                        guard let lib = self.lib else {
                                                throw GoEngineError.newLibReturnedNil
                                        }
                                        
                                        try lib.initApp(config)
                                        
                                        cont.resume()
                                } catch {
                                        cont.resume(throwing: error)
                                }
                        }
                }
        }
}

// MARK: - VPN status (for HomeTabView etc.)
extension GoEngine {
        /// 返回当前 VPN 状态，供 UI 使用；若尚未就绪或为 Stub 则返回占位。
        func getVpnStatus() async -> VpnStatus? {
                do {
                        log("getVpnStatus start")
                        try await ensureReady()
                        return await withCheckedContinuation { cont in
                                queue.async {
                                        let status = self.lib?.getVpnStatus()
                                        if let status {
                                                self.log("getVpnStatus success connected=\(status.connected) server=\(status.server)")
                                        } else {
                                                self.log("getVpnStatus success nil")
                                        }
                                        cont.resume(returning: status)
                                }
                        }
                } catch {
                        log("getVpnStatus failed error=\(String(describing: error))")
                        return nil
                }
        }
}

// MARK: - Install bootstrap (debug)
extension GoEngine {
        private static let firstLaunchKey = "meshflux.didRunAfterInstall"
        
        /// 新安装后的第一次启动：清理 Keychain 残留（DEBUG 默认开启）
        static func bootstrapOnFirstLaunchAfterInstall() {
                let ud = UserDefaults.standard
                if ud.bool(forKey: firstLaunchKey) { return }
                ud.set(true, forKey: firstLaunchKey)
                
                try? PINStore.clear()
                try? WalletStore.clear() 
        }
}
