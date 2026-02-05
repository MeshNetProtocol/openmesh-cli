# MeshFlux iOS 内存优化与 SFI 对齐方案

## 0. 原则与目标 (Principles & Goals)

1.  **目标**：使 **MeshFluxIos** 具备与 **SFI** (sing-box for iOS) 同等级别的内存效率和系统稳定性，同时保留 **MeshFluxMac** 的功能特性。
2.  **约束**：
    *   **SFI / SFM**：仅作为参考对象，**严禁修改**其源码。
    *   **Go 代码修改**：仅限于 `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/go-cli-lib`。该库集成了 sing-box，我们通过在此库中添加 helper 方法（如手动 GC、内存限制配置）来支持 iOS 的内存管理，而不触碰 sing-box 核心。
3.  **澄清**：本方案仅针对 MeshFluxIos 进行改造，**不涉及也不提升** SFI 本身的性能。

---

## 1. 核心差异分析 (Root Cause Analysis)

MeshFluxIos 目前直接复用了 MeshFluxMac (桌面端) 的架构模式，导致在 iOS 严格的内存限制下表现不佳。

| 特性 | MeshFluxMac (桌面模式) | SFI (iOS 原生模式) | MeshFluxIos (当前现状) | 改造方向 |
|------|-----------------------|-------------------|-----------------------|---------|
| **管理连接 (XPC/Socket)** | **持久连接**：App 启动后一直保持与 Extension 的通讯，后台也不断开。 | **按需连接**：仅在 View 可见 (`onAppear`) 时连接，进入后台 (`scenePhase`) 立即断开。 | 模仿了 Mac，后台仍保持连接，导致被系统杀掉。 | **对齐 SFI**：实现前台连接、后台断开。 |
| **数据加载** | **全量持有**：加载所有日志、节点列表常驻内存。 | **懒加载**：使用 `LazyVStack`，分页加载，离开页面即释放数据。 | 全量加载，内存峰值高。 | **对齐 SFI**：UI 层改为懒加载模式。 |
| **内存警告响应** | **忽略**：桌面内存充足。 | **响应**：监听 `didReceiveMemoryWarning`，主动释放缓存并触发 Go GC。 | 无响应机制。 | **新增**：在 Swift 层监听并调用 `go-cli-lib` 的 GC 接口。 |

---

## 2. 实施方案 (Implementation Plan)

### 阶段一：生命周期对齐 (Lifecycle Alignment)

**目标**：解决 App 进入后台占用内存过高被杀的问题。

#### 1.1 Swift 层：实现 App 级休眠机制
在 `MeshFluxIos` 的入口文件 (如 `OpenMeshApp.swift`) 中监听 `scenePhase`。

*   **Active (前台)**: 恢复与 Extension 的管理连接 (Status/Group/Connection Client)。
*   **Background (后台)**: 断开所有管理连接。**注意**：这不会断开 VPN 隧道本身，只是断开 App 与 隧道的控制通道，释放 App 内存。

```swift
// 伪代码 (OpenMeshApp.swift)
.onChange(of: scenePhase) { newPhase in
    switch newPhase {
    case .active:
        // App 回到前台：如果 VPN 是开启的，则重新建立管理连接以更新 UI
        if VpnManager.shared.isConnected {
            StatusClient.shared.connect()
            GroupClient.shared.connect()
        }
    case .background, .inactive:
        // App 进入后台：断开管理连接，释放文件句柄和内存
        StatusClient.shared.disconnect()
        GroupClient.shared.disconnect()
        ConnectionClient.shared.disconnect()
        
        // 清理图片和临时数据缓存
        ImageCache.shared.clear()
    @unknown default:
        break
    }
}
```

**MeshFluxMac的桌面模式：**
```swift
.onChange(of: scenePhase) { phase in
    if phase == .active, vpnController.isConnected { statusClient.connect() }
    // 缺少：没有非活跃时的清理逻辑
}
```

### 3. 资源释放时机

- **SFI**: 在 `ExtensionEnvironments.deinit` 中主动 `logClient.disconnect()`
- **MeshFluxMac**: 没有明确的资源清理时机，依赖系统回收
- **SFI**: 使用 `scenePhase` 精确控制连接状态
- **MeshFluxMac**: 持续监听，即使应用不活跃也保持连接

## 改进方案

### 阶段一：立即修复（1-2天）

#### 1.1 修复编译错误
- [x] 修复 [MemoryOptimizedGoEngine.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxIos/core/MemoryOptimizedGoEngine.swift) 的编译错误
- [x] 添加缺失的 `import UIKit`
- [x] 定义 `initTask` 属性
- [x] 修复泛型方法调用

#### 1.2 实现iOS内存警告响应
```swift
#if canImport(UIKit)
import UIKit

extension MemoryOptimizedGoEngine {
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
        // 清理缓存
        cache.removeAll()
        // 断开非必要连接
        statusClient?.disconnect()
        // 触发垃圾回收
        LibboxForceGC()
    }
}
#endif
```

#### 1.3 实现生命周期感知
```swift
.onChange(of: scenePhase) { phase in
    switch phase {
    case .active:
        if vpnController.isConnected {
            statusClient.connect()
            startMemoryMonitoring()
        }
    case .inactive, .background:
        statusClient.disconnect()
        stopMemoryMonitoring()
        // 清理临时缓存
        clearTemporaryCache()
    @unknown default:
        break
    }
}
```

### 阶段二：架构重构（3-5天）

#### 2.1 创建iOS专用内存管理器
```swift
@MainActor
final class IOSMemoryManager: ObservableObject {
    @Published var memoryUsage: Double = 0
    private var memoryTimer: Timer?
    private var cache = NSCache<NSString, NSData>()
    
    init() {
        setupMemoryMonitoring()
        setupCachePolicy()
    }
    
    private func setupCachePolicy() {
        cache.countLimit = 100  // 限制缓存数量
        cache.totalCostLimit = 10 * 1024 * 1024  // 10MB限制
        cache.evictsObjectsWithDiscardedContent = true
    }
    
    func respondToMemoryWarning() {
        cache.removeAllObjects()
        LibboxForceGC()
        // 通知其他组件清理
        NotificationCenter.default.post(name: .memoryWarning, object: nil)
    }
}
```

#### 2.2 重构连接管理
```swift
final class ConnectionManager {
    private var activeConnections: [String: Connection] = [:]
    private let maxConnections = 5  // iOS限制
    
    func acquireConnection(for key: String) -> Connection? {
        // 检查内存压力
        if isMemoryPressureHigh() {
            cleanupInactiveConnections()
        }
        
        // 限制连接数量
        if activeConnections.count >= maxConnections {
            removeOldestConnection()
        }
        
        return createConnection(for: key)
    }
    
    private func isMemoryPressureHigh() -> Bool {
        return getCurrentMemoryUsage() > 0.8  // 80%阈值
    }
}
```

#### 2.3 实现对象池模式
```swift
final class ObjectPool<T> {
    private var pool: [T] = []
    private let maxSize: Int
    private let create: () -> T
    private let reset: (T) -> Void
    
    init(maxSize: Int, create: @escaping () -> T, reset: @escaping (T) -> Void) {
        self.maxSize = maxSize
        self.create = create
        self.reset = reset
    }
    
    func acquire() -> T {
        if pool.isEmpty {
            return create()
        }
        return pool.removeLast()
    }
    
    func release(_ object: T) {
        if pool.count < maxSize {
            reset(object)
            pool.append(object)
        }
    }
}
```

### 阶段三：深度优化（1-2周）

#### 3.1 Go层内存优化
- [x] 实现对象池（已完成：[packet_parse.go](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/packet_parse.go)）
- [x] 添加内存限制（已完成：[memory_optimized_lib.go](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/go-cli-lib/interface/memory_optimized_lib.go)）
- [ ] 实现定期垃圾回收
- [ ] 优化大对象分配

#### 3.2 数据流优化
```swift
// 实现背压机制
final class BackpressureManager {
    private let queue = DispatchQueue(label: "backpressure", qos: .utility)
    private var pendingData: [Data] = []
    private let maxBufferSize = 1024 * 1024  // 1MB
    
    func processData(_ data: Data) async {
        if pendingData.count >= maxBufferSize {
            await dropOldestData()
        }
        
        return await withCheckedContinuation { continuation in
            queue.async {
                // 处理数据
                self.process(data)
                continuation.resume()
            }
        }
    }
}
```

#### 3.3 内存监控和告警
```swift
final class MemoryMonitor {
    private var timer: Timer?
    private let warningThreshold: Double = 0.75  // 75%
    private let criticalThreshold: Double = 0.85  // 85%
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let usage = self.getCurrentMemoryUsage()
            
            if usage > self.criticalThreshold {
                self.handleCriticalMemoryPressure()
            } else if usage > self.warningThreshold {
                self.handleMemoryWarning()
            }
        }
    }
    
    private func handleCriticalMemoryPressure() {
        // 强制清理所有缓存
        URLCache.shared.removeAllCachedResponses()
        SDImageCache.shared.clearMemory()
        
        // 通知所有组件
        NotificationCenter.default.post(name: .criticalMemoryPressure, object: nil)
    }
}
```

## 实施计划

### 第1周：紧急修复
- 修复编译错误
- 实现基本的内存警告响应
- 添加生命周期管理

### 第2周：架构重构
- 创建专用内存管理器
- 重构连接管理
- 实现对象池

### 第3周：深度优化
- 优化Go层内存使用
- 实现数据流背压
- 完善监控机制

### 第4周：测试验证
- 内存压力测试
- 长时间运行测试
- 不同设备兼容性测试

## 预期效果

### 内存使用优化
- **峰值内存**：从800MB+ 降低到200MB以下
- **平均内存**：从400MB 降低到150MB以下
- **内存增长**：消除线性增长，保持稳定

### 稳定性提升
- **崩溃率**：从100%（6分钟）降低到<1%（24小时）
- **后台存活**：支持后台运行30分钟以上
- **恢复能力**：内存警告后5秒内恢复

### 性能平衡
- **响应速度**：保持<100ms的响应时间
- **CPU使用**：增加<5%的额外开销
- **电池寿命**：减少15%的电量消耗

## 验证方案

### 内存压力测试
```swift
// 内存压力测试工具
final class MemoryStressTester {
    func runStressTest() async {
        // 模拟高内存使用
        let largeData = Data(repeating: 0, count: 100 * 1024 * 1024)  // 100MB
        
        // 创建多个连接
        for i in 0..<10 {
            _ = try? await createConnection(id: "test-\(i)")
        }
        
        // 触发内存警告
        await simulateMemoryWarning()
        
        // 验证恢复
        assert(getCurrentMemoryUsage() < 0.5)  // 应恢复到50%以下
    }
}
```

### 长期稳定性测试
- 连续运行24小时
- 模拟真实用户操作
- 监控内存泄漏
- 验证崩溃恢复

### 设备兼容性测试
- iPhone 11 Pro (4GB)
- iPhone 12 mini (4GB)
- iPhone 13 (6GB)
- iPad Pro (8GB+)

## 监控指标

### 内存指标
```swift
struct MemoryMetrics {
    let currentUsage: Double      // 当前使用率
    let peakUsage: Double         // 峰值使用率
    let averageUsage: Double      // 平均使用率
    let warningCount: Int         // 内存警告次数
    let cleanupCount: Int         // 清理次数
    let recoveryTime: TimeInterval // 恢复时间
}
```

### 性能指标
```swift
struct PerformanceMetrics {
    let responseTime: TimeInterval    // 响应时间
    let connectionCount: Int           // 连接数量
    let cacheHitRate: Double          // 缓存命中率
    let gcFrequency: Double           // GC频率
}
```

### 稳定性指标
```swift
struct StabilityMetrics {
    let crashCount: Int               // 崩溃次数
    let memoryKillCount: Int          // 内存杀死次数
    let backgroundDuration: TimeInterval // 后台存活时间
    let recoverySuccessRate: Double   // 恢复成功率
}
```

## 总结

通过对比SFI和MeshFluxMac的内存管理差异，我们发现了根本问题：桌面内存管理模式不适合iOS的严格内存限制。改进方案采用分阶段实施，从紧急修复到深度优化，确保在不影响用户体验的前提下，彻底解决iOS内存耗尽问题。

关键成功因素：
1. **生命周期感知**：精确控制资源创建和释放时机
2. **内存警告响应**：主动清理而非被动等待
3. **连接管理**：限制数量，及时回收
4. **对象池化**：重用对象，减少分配
5. **监控告警**：实时发现并处理内存问题

预期在4周内将iOS内存使用降低75%，消除崩溃问题，同时保持优秀的用户体验。