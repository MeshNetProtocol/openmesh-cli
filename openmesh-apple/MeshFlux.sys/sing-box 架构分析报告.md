# sing-box SFM vs SFM.System 架构分析报告

## 核心发现

**结论**: sing-box 的 SFM (应用级) 和 SFM.System (系统级) **完全共享 UI 代码**，采用**三层 Framework 架构**实现代码复用。

---

## 架构设计

### 1. 项目结构概览

```
sing-box/clients/apple/
├── SFM/                          # 应用级 NetworkExtension 主程序
│   ├── Application.swift         # 仅 206 字节，只引用 MacLibrary
│   ├── Info.plist
│   └── SFM.entitlements
│
├── SFM.System/                   # 系统级 Extension 主程序
│   ├── Application.swift         # 仅 231 字节，只引用 MacLibrary + Library
│   ├── StandaloneApplicationDelegate.swift  # 系统级特有 delegate
│   ├── Info.plist
│   └── SFM.entitlements
│
├── MacLibrary/                   # macOS 专用 UI 框架（关键共享层）
│   ├── MacApplication.swift      # 共享的主界面（MenuBarExtra + Window）
│   ├── MainView.swift            # 主视图
│   ├── MenuView.swift            # 菜单栏视图
│   ├── SidebarView.swift         # 侧边栏视图
│   ├── ApplicationDelegate.swift # 应用委托
│   └── Assets.xcassets/          # 资源文件
│
├── ApplicationLibrary/           # 跨平台 UI 组件库
│   ├── Views/
│   │   ├── Dashboard/            # 仪表盘视图
│   │   ├── Profile/              # 配置管理视图
│   │   ├── Groups/               # 群组视图
│   │   ├── Log/                  # 日志视图
│   │   ├── Connections/          # 连接监控视图
│   │   ├── Setting/              # 设置视图
│   │   └── ...
│   └── Service/                  # 业务逻辑层
│
├── Library/                      # 底层共享库（数据模型、工具类）
│   ├── Database/                 # 数据库相关
│   ├── Network/                  # 网络相关
│   ├── Shared/                   # 共享工具
│   └── Discovery/                # 服务发现
│
└── Extension/                    # 扩展（VPN Provider）
└── SystemExtension/              # 系统扩展
```

---

## 代码共享机制

### 2. 三层 Framework 架构

#### 第一层：Library (最底层)
**职责**: 提供基础数据模型、工具类、网络服务等
- ✅ Database: 数据库操作
- ✅ Network: 网络通信
- ✅ Shared: 共享工具函数
- ✅ Discovery: 服务发现

**特点**:
- 纯 Swift 代码，无 UI 组件
- 跨平台（iOS/macOS 通用）
- 被所有上层 Framework 引用

#### 第二层：ApplicationLibrary (中间层)
**职责**: 提供可复用的 UI 组件和业务逻辑
- ✅ Views/: 所有可复用的视图组件
  - Dashboard/, Profile/, Groups/, Log/, Connections/, Setting/
- ✅ Service/: 业务逻辑服务
- ✅ Assets.xcassets/: 共享资源

**特点**:
- 包含完整的 UI 组件，但不包含 App 入口
- 跨平台（iOS/macOS 通用）
- 依赖 Library
- 被 MacLibrary 和 iOS 相关 Target 引用

#### 第三层：MacLibrary (最上层 - macOS 专用)
**职责**: 提供 macOS 专用的 App 入口和主界面
- ✅ MacApplication.swift: **核心共享组件**
  - 定义 MenuBarExtra（菜单栏）
  - 定义 Window（主窗口）
  - 使用 MainView, MenuView, SidebarView
- ✅ MainView.swift: 主视图容器
- ✅ MenuView.swift: 菜单视图
- ✅ SidebarView.swift: 侧边栏视图
- ✅ ApplicationDelegate.swift: macOS 专用 delegate

**特点**:
- 仅用于 macOS
- 依赖 ApplicationLibrary 和 Library
- **SFM 和 SFM.System 都引用这个 Framework**

---

## 代码对比

### 3. SFM vs SFM.System 的 Application.swift

#### SFM (应用级):
```swift
// SFM/Application.swift (206 bytes)
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate

    var body: some Scene {
        MacApplication()  // ← 直接使用共享的 MacApplication
    }
}
```

#### SFM.System (系统级):
```swift
// SFM.System/Application.swift (231 bytes)
import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: StandaloneApplicationDelegate

    var body: some Scene {
        MacApplication()  // ← 同样使用共享的 MacApplication
    }
}
```

**差异**:
1. SFM.System 额外 import Library（可能需要访问底层服务）
2. SFM.System 使用 `StandaloneApplicationDelegate`（系统级特殊处理）
3. **但两者都使用完全相同的 `MacApplication()` 作为主界面**

---

## 关键洞察

### 4. 为什么选择完全共享 UI？

#### 优势：
1. **维护成本低**: 只需维护一套 UI 代码
2. **一致性保证**: SFM 和 SFM.System 的用户体验完全一致
3. **快速迭代**: UI 更新同时应用到两个 Target
4. **减少 Bug**: 修复一个 UI bug，两个 Target 都受益

#### 代价：
1. **无法定制化**: SFM 和 SFM.System 的界面必须完全相同
2. **Framework 复杂度高**: 需要精心设计依赖关系
3. **编译时间增加**: Framework 需要单独构建

#### 适用场景：
✅ **适合 sing-box**: VPN 工具类应用，UI 相对标准化
✅ **适合 MeshFlux**: 同样是 VPN 工具，UI 需求一致

❌ **不适合**: 如果两个 Target 需要完全不同的 UI 风格或交互流程

---

## MeshFlux 现状对比

### 5. MeshFluxMac vs MeshFlux.sys

#### 当前状态：
```
MeshFluxMac/
├── OpenMeshMacApp.swift        # ~18KB，完整的应用入口
├── core/                       # 核心逻辑层
├── views/                      # 21 个 UI 文件
└── ...

MeshFlux.sys/
├── OpenMesh_SysApp.swift       # ~2.7KB，简化的应用入口
├── SystemExtensionManager.swift # ~25KB，系统级 extension 管理
├── ContentView.swift           # ~14KB，简单 UI
└── ...

SharedCode/                     # 部分共享代码（已被两个 Target 引用）
├── MarketService.swift
├── ConfigModePatch.swift
├── ProfileFromShared.swift
└── ...
```

#### 与 sing-box 对比：

| 特性 | sing-box | MeshFlux (当前) |
|------|----------|-----------------|
| **UI 共享策略** | 完全共享（MacLibrary） | 部分共享（SharedCode 仅业务逻辑） |
| **App 入口** | 极简（~200 字节） | 完整实现（~18KB vs ~2.7KB） |
| **Framework 分层** | 三层（Library → ApplicationLibrary → MacLibrary） | 一层（VPNLibrary） |
| **Views 位置** | ApplicationLibrary/Views（共享） | MeshFluxMac/views（独占） |

---

## 建议方案

### 6. 对 MeshFlux 的启示

基于 sing-box 的成功经验，建议 MeshFlux 采用以下策略：

#### 方案 A：完全共享 UI（推荐）⭐

**步骤**:
1. 将 `MeshFluxMac/views/` 移动到新建的 `MeshFluxUI/` 目录
2. 创建 `MeshFluxUI.framework` Framework Target
3. 让 `MeshFluxMac` 和 `MeshFlux.sys` 都引用这个 Framework
4. 简化两个 App 入口为极简代码（类似 sing-box）

**优点**:
- ✅ 代码复用率最高
- ✅ 维护成本最低
- ✅ 与 sing-box 架构一致，便于参考
- ✅ 符合您的"刚性要求 1"（不影响其他工程）

**缺点**:
- ❌ 需要重构 Xcode 项目
- ❌ MeshFluxMac 和 MeshFlux.sys 界面必须完全一致

#### 方案 B：保持独立（次选）

**步骤**:
1. 从 MeshFluxMac 复制 views/ 到 MeshFlux.sys/views/
2. 各自维护独立的 UI 代码
3. 通过 SharedCode 共享必要的业务逻辑

**优点**:
- ✅ 两个 App 可以有差异化 UI
- ✅ 实施简单，不需要重构 Framework

**缺点**:
- ❌ 代码重复，维护成本高
- ❌ 不符合 sing-box 的最佳实践

---

## 详细实施路径（方案 A）

### 7. 如果选择完全共享 UI

#### Phase 0: 创建 MeshFluxUI Framework（新增）
```bash
# 创建新目录
mkdir -p ../MeshFluxUI/Views
mkdir -p ../MeshFluxUI/Core

# 移动 UI 文件
mv ../MeshFluxMac/views/* ../MeshFluxUI/Views/
mv ../MeshFluxMac/core/* ../MeshFluxUI/Core/
```

#### Phase 1: 更新 Xcode 项目
1. 在 `MeshFlux.xcodeproj` 中添加新的 Framework Target
2. 配置 Framework Search Paths
3. 让 MeshFluxMac 和 MeshFlux.sys 都引用 `MeshFluxUI.framework`

#### Phase 2: 简化 App 入口
```swift
// MeshFluxMac/OpenMeshMacApp.swift (简化后)
import MeshFluxUI
import SwiftUI

@main
struct OpenMeshApp: App {
    var body: some Scene {
        MeshFluxMainView()  // ← 使用共享 UI
    }
}

// MeshFlux.sys/OpenMesh_SysApp.swift (简化后)
import MeshFluxUI
import SwiftUI

@main
struct OpenMeshSysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MeshFluxMainView()  // ← 使用相同的共享 UI
    }
}
```

#### Phase 3: 处理差异
如果 MeshFlux.sys 有特殊的系统级需求（如 Onboarding），可以在共享 UI 基础上通过条件编译或运行时判断来处理：

```swift
// MeshFluxUI/Views/MainView.swift
struct MainView: View {
    #if SYSTEM_EXTENSION
    @StateObject private var extensionManager = SystemExtensionManager.shared
    #endif
    
    var body: some View {
        if needsOnboarding {
            OnboardingView()
        } else {
            StandardMainView()
        }
    }
}
```

---

## 结论

**sing-box 的成功实践证明**: 
- SFM 和 SFM.System **完全共享 UI** 是可行的且高效的
- 通过三层 Framework 架构（Library → ApplicationLibrary → MacLibrary）实现代码最大化复用
- App 入口可以简化到只有 ~200 字节

**对 MeshFlux 的建议**:
1. **优先采用方案 A**（完全共享 UI），创建 `MeshFluxUI.framework`
2. **参考 sing-box 的架构**，将 UI 组件移到共享 Framework
3. **保持刚性要求**：不修改 SharedCode/，所有改动限制在 MeshFluxUI 新建目录内

---

**分析完成时间**: 2026-03-05  
**参考项目**: sing-box SFM / SFM.System  
**分析者**: AI Assistant
