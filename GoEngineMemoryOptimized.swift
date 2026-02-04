// 内存优化补丁 - 直接修改现有GoEngine
// 使用方法：将这些修改应用到现有的GoEngine.swift文件中

import Foundation
import OpenMeshGo

enum GoEngineError: LocalizedError {
    /// 核心库（OpenMeshGo）加载失败，无法使用钱包与 VPN 能力。
    case newLibReturnedNil
    case configTooLarge
    
    var errorDescription: String? {
        switch self {
        case .newLibReturnedNil:
            return "无法加载核心库，请重新安装应用或联系支持。"
        case .configTooLarge:
            return "配置数据过大，请检查配置文件。"
        }
    }
}

final class GoEngine {
    static let shared = GoEngine()
    
    private let queue = DispatchQueue(label: "meshflux.go.engine.serial")
    private let memoryQueue = DispatchQueue(label: "meshflux.memory.monitor", qos: .background)
    
    private var lib: (any OpenmeshAppLibProtocol)?
    private var cachedConfig: Data = Data()
    
    // 内存管理相关
    private var lastMemoryWarningTime: Date = Date.distantPast
    private var totalMemoryAllocated: Int64 = 0
    private static let maxConfigSize = 5 * 1024 * 1024 // 5MB限制
    private static let memoryWarningInterval: TimeInterval = 30.0
    
    private var initTask: Task<Void, Error>?
    
    private init() {
        self.cachedConfig = Data()
        self.initTask = Task { [weak self] in
            guard let self else { return }
            try await self.initLocked(config: self.cachedConfig)
        }
        
        // 注册内存警告通知
        setupMemoryWarningHandler()
    }
    
    // MARK: - Memory Management
    private func setupMemoryWarningHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryWarningTime) > GoEngine.memoryWarningInterval else { return }
        
        lastMemoryWarningTime = now
        
        memoryQueue.async { [weak self] in
            self?.performMemoryCleanup()
        }
    }
    
    private func performMemoryCleanup() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 清理配置缓存但不重置核心库
            if self.cachedConfig.count > 1024 * 1024 { // 如果配置大于1MB
                self.cachedConfig = Data() // 清理缓存，需要时重新加载
            }
            
            // 强制垃圾回收（iOS会自动处理，这里只是标记）
            self.totalMemoryAllocated = 0
        }
    }
    
    // MARK: - Memory-Aware API Methods
    func generateMnemonic12() async throws -> String {
        try await ensureReady()
        
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: GoEngineError.newLibReturnedNil)
                    return
                }
                
                do {
                    guard let lib = self.lib else {
                        throw GoEngineError.newLibReturnedNil
                    }
                    
                    let result = try lib.generateMnemonic12()
                    
                    // 跟踪内存使用（估算）
                    self.totalMemoryAllocated += Int64(result.count * 2)
                    
                    cont.resume(returning: result)
                    
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    func decryptEvmWallet(keystoreJSON: String, pin: String) async throws -> WalletSecretsV1 {
        try await ensureReady()
        
        // 检查输入数据大小
        guard keystoreJSON.count < 100 * 1024 else { // 100KB限制
            throw GoEngineError.configTooLarge
        }
        
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: GoEngineError.newLibReturnedNil)
                    return
                }
                
                do {
                    guard let lib = self.lib else {
                        throw GoEngineError.newLibReturnedNil
                    }
                    
                    let secrets = try lib.decryptEvmWallet(keystoreJSON, password: pin)
                    
                    // 跟踪内存使用
                    self.totalMemoryAllocated += Int64(MemoryLayout<WalletSecretsV1>.size)
                    
                    cont.resume(returning: secrets)
                    
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    func reconfigure(config: Data) async throws {
        // 内存检查：限制配置大小
        guard config.count < GoEngine.maxConfigSize else {
            throw GoEngineError.configTooLarge
        }
        
        // 清理旧配置
        if cachedConfig.count > 0 {
            totalMemoryAllocated -= Int64(cachedConfig.count)
        }
        
        // 设置新配置
        cachedConfig = config
        totalMemoryAllocated += Int64(config.count)
        
        try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                self?.initTask = Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await self.initLocked(config: config)
                    } catch {
                        // 如果重配置失败，清理缓存
                        self.totalMemoryAllocated -= Int64(config.count)
                        self.cachedConfig = Data()
                    }
                }
                cont.resume()
            }
        }
        
        try await ensureReady()
    }
    
    func reset() async {
        await withCheckedContinuation { cont in
            queue.async { [weak self] in
                guard let self = self else {
                    cont.resume()
                    return
                }
                
                // 完全清理所有资源
                self.lib = nil
                self.totalMemoryAllocated -= Int64(self.cachedConfig.count)
                self.cachedConfig = Data()
                self.initTask = nil
                self.totalMemoryAllocated = 0
                
                cont.resume()
            }
        }
    }
    
    // MARK: - Internal Methods
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
            queue.async { [weak self] in
                guard let self = self else {
                    cont.resume()
                    return
                }
                
                do {
                    // 内存检查：限制配置大小
                    guard config.count < GoEngine.maxConfigSize else {
                        cont.resume(throwing: GoEngineError.configTooLarge)
                        return
                    }
                    
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

// MARK: - VPN Status Extension
extension GoEngine {
    func getVpnStatus() async -> VpnStatus? {
        do {
            try await ensureReady()
            return lib?.getVpnStatus()
        } catch {
            return nil
        }
    }
    
    // 获取内存使用统计
    func getMemoryStats() -> [String: Any] {
        return [
            "cachedConfigSize": cachedConfig.count,
            "totalMemoryAllocated": totalMemoryAllocated,
            "lastMemoryWarning": lastMemoryWarningTime.timeIntervalSince1970,
            "libraryLoaded": lib != nil
        ]
    }
}

// MARK: - Bootstrap
extension GoEngine {
    private static let firstLaunchKey = "meshflux.didRunAfterInstall"
    
    static func bootstrapOnFirstLaunchAfterInstall() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: firstLaunchKey) { return }
        ud.set(true, forKey: firstLaunchKey)
        
        try? PINStore.clear()
        try? WalletStore.clear()
    }
}