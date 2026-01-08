import Foundation
import OpenMeshGo

enum GoEngineError: LocalizedError {
    case newLibReturnedNil
    case notReadyYet
    
    var errorDescription: String? {
        switch self {
        case .newLibReturnedNil:
            return "OMOpenmeshNewLib() 返回 nil"
        case .notReadyYet:
            return "GoEngine 尚未初始化完成"
        }
    }
}

final class GoEngine {
    static let shared = GoEngine()
    
    private let queue = DispatchQueue(label: "openmesh.go.engine.serial")
    
    private var lib: OMOpenmeshAppLib?
    private var cachedConfig: Data = Data()
    
    private var initTask: Task<Void, Error>?
    
    private init() {
        self.cachedConfig = Data()
        self.initTask = Task { [weak self] in
            guard let self else { return }
            try await self.initLocked(config: self.cachedConfig)
        }
    }
    
    func generateMnemonic12() async throws -> String {
        try await ensureReady()
        
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    guard let lib = self.lib else {
                        throw GoEngineError.newLibReturnedNil
                    }
                    
                    var err: NSError?
                    let s = lib.generateMnemonic12(&err)
                    if let err = err { throw err }
                    
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
                    
                    var err: NSError?
                    // gomobile 生成的 Swift 方法名通常是：createEvmWallet(_:pin:error:)
                    let json = lib.createEvmWallet(mnemonic, pin: pin, error: &err)
                    if let err = err { throw err }
                    
                    cont.resume(returning: json)
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
                        self.lib = OMOpenmeshNewLib()
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

// MARK: - Install bootstrap (debug)
extension GoEngine {
    private static let firstLaunchKey = "openmesh.didRunAfterInstall"
    
    /// 新安装后的第一次启动：清理 Keychain 残留（DEBUG 默认开启）
    static func bootstrapOnFirstLaunchAfterInstall() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: firstLaunchKey) { return }
        ud.set(true, forKey: firstLaunchKey)
        
        try? PINStore.clear()
        try? WalletStore.clear() 
    }
}
