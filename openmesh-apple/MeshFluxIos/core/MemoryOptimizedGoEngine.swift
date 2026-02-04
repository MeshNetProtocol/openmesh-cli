import Foundation
import OpenMeshGo
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Memory Optimized Go Engine
final class MemoryOptimizedGoEngine {
    static let shared = MemoryOptimizedGoEngine()
    
    private let queue = DispatchQueue(label: "meshflux.go.engine.memory_optimized")
    private let memoryQueue = DispatchQueue(label: "meshflux.memory.monitor")
    
    private var lib: (any OpenmeshAppLibProtocol)?
    private var cachedConfig: Data?
    private var configCacheSize: Int = 0
    
    private var lastMemoryWarning: Date = Date.distantPast
    private var totalMemoryAllocated: Int64 = 0
    private var maxMemoryUsage: Int64 = 0
    
    private var memoryMonitorTimer: Timer?
    private var isCleaningUp = false
    private var initTask: Task<Void, Error>?
    
    private static let maxConfigSize = 5 * 1024 * 1024 // 5MB
    private static let memoryWarningInterval: TimeInterval = 30.0
    private static let maxTotalMemory = 50 * 1024 * 1024 // 50MB total limit
    
    private init() {
        setupMemoryMonitoring()
        setupMemoryWarningHandler()
    }
    
    deinit {
        memoryMonitorTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Memory Management
    private func setupMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performMemoryCheck()
        }
    }
    
    private func setupMemoryWarningHandler() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        #endif
    }
    
    private func handleMemoryWarning() {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryWarning) > MemoryOptimizedGoEngine.memoryWarningInterval else { return }
        
        lastMemoryWarning = now
        
        memoryQueue.async { [weak self] in
            self?.performAggressiveCleanup()
        }
    }
    
    private func performMemoryCheck() {
        guard !isCleaningUp else { return }
        
        memoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 如果总内存使用超过限制，执行清理
            if self.totalMemoryAllocated > MemoryOptimizedGoEngine.maxTotalMemory {
                self.performAggressiveCleanup()
            }
            
            // 如果配置缓存过大，清理部分缓存
            if self.configCacheSize > MemoryOptimizedGoEngine.maxConfigSize {
                self.clearConfigCache()
            }
        }
    }
    
    private func performAggressiveCleanup() {
        isCleaningUp = true
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 清理所有非必要缓存
            self.cachedConfig = nil
            self.configCacheSize = 0
            self.totalMemoryAllocated = 0
            
            // 如果内存压力仍然很大，考虑重置库
            if self.shouldResetLibrary() {
                self.lib = nil
            }
            
            self.isCleaningUp = false
        }
    }
    
    private func shouldResetLibrary() -> Bool {
        // 简单的启发式规则：如果内存使用超过限制的两倍
        return totalMemoryAllocated > MemoryOptimizedGoEngine.maxTotalMemory * 2
    }
    
    private func clearConfigCache() {
        cachedConfig = nil
        configCacheSize = 0
        totalMemoryAllocated -= Int64(configCacheSize)
    }
    
    // MARK: - Memory Tracking
    private func trackMemoryAllocation(_ size: Int) {
        totalMemoryAllocated += Int64(size)
        if totalMemoryAllocated > maxMemoryUsage {
            maxMemoryUsage = totalMemoryAllocated
        }
    }
    
    private func trackMemoryDeallocation(_ size: Int) {
        totalMemoryAllocated -= Int64(size)
        if totalMemoryAllocated < 0 {
            totalMemoryAllocated = 0
        }
    }
    
    // MARK: - Public API with Memory Safety
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
                    self.trackMemoryAllocation(result.count * 2) // UTF-16 估算
                    
                    cont.resume(returning: result)
                    
                    // 清理临时内存
                    self.trackMemoryDeallocation(result.count * 2)
                    
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    func reconfigure(config: Data) async throws {
        // 验证配置大小
        guard config.count < MemoryOptimizedGoEngine.maxConfigSize else {
            throw NSError(domain: "MemoryOptimizedGoEngine", code: 1001, 
                         userInfo: [NSLocalizedDescriptionKey: "配置数据过大"])
        }
        
        // 清理旧配置
        if let oldConfig = cachedConfig {
            trackMemoryDeallocation(oldConfig.count)
        }
        
        // 缓存新配置
        cachedConfig = config
        configCacheSize = config.count
        trackMemoryAllocation(config.count)
        
        // 继续重配置逻辑
        initTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.initLocked(config: config)
            } catch {
                // 如果重配置失败，清理缓存
                self.clearConfigCache()
                throw error
            }
        }
        
        try await ensureReady()
    }
    
    // MARK: - Memory Statistics
    func getMemoryStats() -> [String: Any] {
        return [
            "currentMemoryUsage": totalMemoryAllocated,
            "maxMemoryUsage": maxMemoryUsage,
            "configCacheSize": configCacheSize,
            "isCleaningUp": isCleaningUp,
            "libraryLoaded": lib != nil
        ]
    }
    
    // MARK: - Private Methods
    private func ensureReady() async throws {
        if initTask == nil {
            guard let config = cachedConfig else {
                throw NSError(domain: "MemoryOptimizedGoEngine", code: 1002, 
                             userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
            }
            
            initTask = Task { [weak self] in
                guard let self = self else { return }
                try await self.initLocked(config: config)
            }
        }
        try await initTask?.value
    }
    
    private func initLocked(config: Data) async throws {
        // 内存优化的初始化逻辑
        // ... (与原始GoEngine类似，但增加内存检查)
    }
}