# MeshFluxMac → MeshFluxIos（VPN 功能与界面）迁移方案（工作文档）

## 需求摘要（1 段话）

目标是在不影响 `openmesh-apple/MeshFluxIos` 现有「区块链界面与能力」的前提下，将 `openmesh-apple/MeshFluxMac` target 里当前已实现且经过优化的「VPN 功能与界面」完整迁移到 `openmesh-apple/MeshFluxIos` target：允许将 MeshFluxIos 中现有的 VPN 功能与界面全部清除并替换为 MeshFluxMac 方案，同时考虑 macOS App 与 iOS App 在内存管理与系统 API（尤其是 NetworkExtension/VPN 相关能力）的差异；迁移过程中需要参考 `sing-box/clients/apple/SFI` target 的 API 用法（其同样与 sing-box 的 Go 代码交互），并以 `go-cli-lib`（封装区块链钱包 Go 代码 + sing-box Go 代码）作为 MeshFluxMac/MeshFluxIos 共用的 Go 侧能力来源；最终输出应是一份其它 AI/工程师可读、可按步骤实施且每步可验证/可测试的迁移方案文档。

## 本文档交付物

- 代码现状盘点：MeshFluxMac、MeshFluxIos、SFI、go-cli-lib、sing-box 的关键入口与依赖关系
- 迁移目标与边界：保留/删除/替换清单（尤其是 iOS 端区块链模块必须保留）
- 迁移架构方案：iOS 上 VPN 栈/Go 桥接/配置模型/UI 的落位方式
- 分阶段迁移步骤：每一步包含可执行动作、预期结果、测试方法、回滚点
- 风险清单与规避策略：包含平台差异、权限/签名/Extension、资源与内存等

## 约定与缩写

- **Mac Target**：`openmesh-apple/MeshFluxMac`
- **iOS Target**：`openmesh-apple/MeshFluxIos`
- **参考 Target（SFI）**：`sing-box/clients/apple/SFI`
- **Go 能力库**：`go-cli-lib`
- **sing-box 源码**：`sing-box`

## 概览

本文档已完成基础代码盘点与关键差异分析；下文给出可执行、可逐步测试的迁移方案（按阶段实施），并在每一步明确验证方法与回滚点。

---

## 1. 现状盘点（以代码为准）

### 1.1 MeshFluxMac（VPN + UI 已优化）

- App 入口：`openmesh-apple/MeshFluxMac/OpenMeshMacApp.swift`
  - 关键点：与 sing-box 一致，把 `OMLibboxSetup(...)`、`NETunnelProviderManager.loadAllFromPreferences(...)` 等可能触发 CFPrefs/沙盒错误的动作延后到 `applicationDidFinishLaunching` 之后（通过 `.appLaunchDidFinish` 通知）。
- VPN 控制层：
  - `openmesh-apple/MeshFluxMac/core/VPNController.swift`
    - 优先使用 `VPNLibrary/ExtensionProfile`（通知驱动状态，不轮询）；如 extension 未加载则 fallback 到 legacy `VPNManager`。
    - 提供扩展能力：`requestExtensionReload()`、`requestURLTest()`、`reconnectToApplySettings()` 等。
  - `openmesh-apple/MeshFluxMac/core/VPNManager.swift`
    - 直接使用 `NETunnelProviderManager` 管理 profile/连接，并包含若干稳定性优化：
      - **defer loadAllFromPreferences**（避免 init 阶段访问 CFPrefs）。
      - **configNonce** 写入 `providerConfiguration` 强制 preference 更新（避免签名/entitlement 变化导致系统继续使用旧配置）。
      - `sendProviderMessage`：reload / 更新规则 / urltest（mac extension 支持）。
- UI（对齐 sing-box Apple 客户端信息结构）：
  - `openmesh-apple/MeshFluxMac/views/NavigationPage.swift`：Dashboard / Groups / Connections / Logs / Profiles / Settings
  - `openmesh-apple/MeshFluxMac/views/DashboardView.swift`：连接状态 + 状态网格（内存/协程/连接数/流量）
  - Profiles/Groups/Connections/Settings 等页面均基于 `VPNLibrary` 的 Profile/SharedPreferences/CommandClient 能力。
- 与 extension 的状态/组/连接通信：
  - `openmesh-apple/MeshFluxMac/core/StatusCommandClient.swift`
  - `openmesh-apple/MeshFluxMac/core/GroupCommandClient.swift`（包含 **stableInput 深拷贝 + tag 校验**，用于防止 Swift↔GoMobile 交互的瞬态 buffer 共享导致崩溃）
  - `openmesh-apple/MeshFluxMac/core/ConnectionCommandClient.swift`
  - `openmesh-apple/MeshFluxMac/core/LogCommandClient.swift`

### 1.2 MeshFluxIos（需保留区块链，VPN UI/功能允许清空）

- App 入口：`openmesh-apple/MeshFluxIos/OpenMeshApp.swift`
  - 关键点：当前在 SwiftUI `.onAppear` 中调用 `OMLibboxSetup(...)`（存在“多次调用/调用时机偏晚”的潜在风险；SFI/上游更倾向放在 AppDelegate 的 `didFinishLaunching`）。
- 区块链/钱包（必须保留）：
  - UI：`openmesh-apple/MeshFluxIos/views/main/MeTabView.swift`（“流量市场”）
  - Go 桥接：`openmesh-apple/MeshFluxIos/core/GoEngine.swift` + `OpenmeshAppLibBridge.swift`
  - PIN/钱包存储：`openmesh-apple/MeshFluxIos/core/PINStore.swift`、`WalletStore.swift` 等
- 现有 VPN UI/功能（允许全部删除并替换）：
  - `openmesh-apple/MeshFluxIos/views/main/HomeTabView.swift`
  - `openmesh-apple/MeshFluxIos/views/SettingsTabView.swift`
  - `openmesh-apple/MeshFluxIos/core/VPNProfileHolder.swift`（封装 `VPNLibrary/ExtensionProfile`）
  - `openmesh-apple/MeshFluxIos/core/GroupCommandClient.swift`（实现较“轻”，缺少 Mac 侧稳定性优化）

### 1.3 参考实现：SFI（sing-box iOS 客户端）

- 入口与 libbox 初始化模式：`sing-box/clients/apple/SFI/ApplicationDelegate.swift`
  - `LibboxSetupOptions` 使用 `FilePath.*.relativePath`，在 `application(_:didFinishLaunchingWithOptions:)` 中完成初始化。
- UI 信息结构：`sing-box/clients/apple/SFI/MainView.swift` + `sing-box/clients/apple/ApplicationLibrary/...`
  - 以 `NavigationPage` + `CommandClient(.status/.groups/.connections/.log)` 驱动页面数据（通知/回调驱动，尽量避免轮询）。

### 1.4 Go/Libbox 交互边界（OpenMeshGo.xcframework）

- iOS/macOS App 与 VPN Extension 都依赖 `openmesh-apple/lib/OpenMeshGo.xcframework`：
  - `OMLibbox*`：来自 sing-box `experimental/libbox`（command server/client、service、status/groups/connections/log 等）
  - `OMOpenmesh*`：来自 `go-cli-lib`（钱包/支付/部分 VPN 状态接口）
- 关键 API（从头文件可见）：
  - `OMLibboxNewCommandClient(...)` / `OMLibboxNewStandaloneCommandClient()`
  - `serviceReload` / `urlTest` / `selectOutbound` / `closeConnections` 等
  - `OMOpenmeshNewLib()` → `initApp(...)` → 钱包相关方法

### 1.5 VPN Extension（iOS vs macOS）

- iOS Extension：`openmesh-apple/vpn_extension_ios/PacketTunnelProvider.swift`
  - 支持 `sendProviderMessage`：`reload` / `update_rules(json)`（**当前不支持 urltest**）
  - `reloadService(...)` 逻辑与 macOS 不完全一致（设置 service 的顺序不同；未先 setService(nil) 再 close old）
- macOS Extension：`openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift`
  - 支持 `sendProviderMessage`：`reload` / `urltest`（自动挑选 groupTag 并回传 delay snapshot）
  - stopTunnel 前先 `setTunnelNetworkSettings(nil)`，降低“残留路由导致下次 not primary”概率
  - 心跳机制：读取 App Group 的 `FilePath.appHeartbeatFile`，主程序退出后可主动停 VPN（该策略是否适用于 iOS 需谨慎评估）

---

## 2. 迁移目标与边界（必须写清）

### 2.1 迁移后 MeshFluxIos 必须具备

- 完整复刻 MeshFluxMac 的 VPN 功能面（Profiles/Groups/Connections/Logs/Settings/Dashboard）及其优化点
- 与 iOS 平台约束一致的实现方式（NetworkExtension、后台限制、内存压力）
- 保留并不破坏 MeshFluxIos 的区块链能力与界面（onboarding、PIN、钱包、USDC 余额、x402 等）

### 2.2 明确允许做的“破坏性改动”

- MeshFluxIos 中现有 VPN 相关 UI/逻辑可全部删除（`HomeTabView`、`SettingsTabView`、相关状态卡片等）
- VPN 入口可改造（例如：把当前 “Home” 变成 “VPN”，或新增 “VPN” Tab）

### 2.3 不做（非目标）

- 不重写 Go/sing-box 本体逻辑（除非为修复 iOS 平台兼容性必须）
- 不改变“流量市场/钱包”业务逻辑与数据结构（仅允许为了新的导航结构做轻量路由调整）

### 2.4 保留 / 删除 / 替换清单（执行前可再校对一次）

- **必须保留（iOS 区块链）**
  - `openmesh-apple/MeshFluxIos/core/GoEngine.swift`、`openmesh-apple/MeshFluxIos/core/OpenmeshAppLibBridge.swift`
  - `openmesh-apple/MeshFluxIos/core/PINStore.swift`、`openmesh-apple/MeshFluxIos/core/WalletStore.swift`
  - `openmesh-apple/MeshFluxIos/views/auth/*`、`openmesh-apple/MeshFluxIos/views/main/MeTabView.swift`
- **允许删除（旧 iOS VPN UI/逻辑）**
  - `openmesh-apple/MeshFluxIos/views/main/HomeTabView.swift`
  - `openmesh-apple/MeshFluxIos/views/SettingsTabView.swift`（如最终改为 Mac 版 Settings）
  - `openmesh-apple/MeshFluxIos/core/VPNProfileHolder.swift`（若改为 `VPNController` 统一承载）
- **将被替换/对齐（迁移 Mac 优化点）**
  - `openmesh-apple/MeshFluxIos/core/GroupCommandClient.swift`（对齐 Mac 的 stableInput/validateTag/发送队列等）
  - `openmesh-apple/MeshFluxIos/core/ConnectionCommandClient.swift`（补齐 Mac 的 closeConnection 等能力视 UI 需要）
  - iOS 侧新增/迁移 `VPNController`、`LogCommandClient`、以及 Mac 的 VPN 页面信息架构（Dashboard/Profiles/Groups/Connections/Settings/(可选 Logs)）

---

## 3. 总体设计（推荐）

### 3.1 关键原则

1. **UI 与 VPN Core 解耦**：VPN 连接/状态/命令通道封装为可复用的 Controller/Clients；UI 只订阅状态并触发动作。
2. **按 SFI/上游模式初始化 libbox**：在 iOS `UIApplicationDelegate` 的 `didFinishLaunching` 中完成 `OMLibboxSetup`，避免 SwiftUI `.onAppear` 多次触发。
3. **迁移“Mac 的稳定性优化”到 iOS**：尤其是 Swift↔GoMobile 的字符串/迭代器数据生命周期问题（深拷贝、tag 校验、避免跨线程持有 Go 对象）。
4. **平台差异显式化**：macOS 才有 NSAlert、菜单栏、TUN 清理；iOS 才有内存告警、路由拆分、前后台切换策略。

### 3.2 iOS 端建议的新结构（示意）

- `MeshFluxIos`
  - **Blockchain 模块（保留）**：现有 `GoEngine`、`WalletStore`、`MeTabView`、onboarding 流程
  - **VPN 模块（替换为 Mac 方案）**：
    - `VPNController`（iOS 版，API 对齐 Mac）
    - `StatusCommandClient / GroupCommandClient / ConnectionCommandClient / LogCommandClient`（优先与 Mac 版本对齐）
    - UI：按 `NavigationPage` 组织成 iOS 适配的页面（Dashboard/Profiles/Groups/Connections/Logs/Settings）

### 3.3 迁移后 iOS 的导航建议

- `TabView` 保留 3 个主入口（推荐）：
  - Tab1：**VPN**（迁移后的 Mac UI/功能）
  - Tab2：**流量市场**（现有 `MeTabView` 保留）
  - Tab3：**设置**（可复用 Mac 的 VPN 设置页；如需钱包设置则另加分组）

---

## 4. 分阶段迁移步骤（每步可测试）

> 每个阶段都要求：能编译、能跑、能验证；必要时可在阶段边界回滚。

### Phase 0：建立基线与测试清单（1 次性）

动作：
1. 在 Xcode 中分别跑通当前 `MeshFluxIos`（含 `vpn_extension_ios`）与 `MeshFluxMac`（含 `vpn_extension_macos`）的连接/断开。
2. 记录关键配置常量（Bundle ID、App Group、Extension 的 `providerBundleIdentifier`、`localizedDescription`）。
3. 把以下“验收用 smoke test”写入 issue/任务板（后续每阶段都跑一遍）。

Smoke test（迁移后必须通过）：
- iOS：钱包创建/导入、PIN 流程、USDC 余额查询（保留能力）
- iOS：VPN 连接/断开；连接后状态卡片刷新；Groups 列表可加载；Connections 列表可加载；Profiles 可切换并生效；Settings 的“本地网络不走 VPN”生效
- iOS：前后台切换后 UI 不崩溃、状态能恢复；低内存告警下不崩溃（可用 Xcode Simulate Memory Warning）

回滚点：无代码改动，只有记录。

### Phase 1：统一 iOS 的 libbox 初始化方式（对齐 SFI）

动机：
- 当前 iOS 在 SwiftUI `.onAppear` 调 `OMLibboxSetup`，可能多次触发且时机不稳定；SFI/上游在 AppDelegate 初始化一次更可靠。

动作（建议）：
1. 为 `MeshFluxIos` 增加 `UIApplicationDelegateAdaptor`，在 `application(_:didFinishLaunchingWithOptions:)` 中调用一次 `OMLibboxSetup`。
2. `OMLibboxSetupOptions` 的路径优先使用 `FilePath.*.relativePath`（与 SFI/macOS extension 更一致），并确认 command.sock 路径长度不会超限。
3. 移除/避免在 SwiftUI `.onAppear` 重复调用 setup（保持幂等：如必须保留，则加“仅执行一次”保护）。

验证：
- 构建并运行 iOS App（真机优先，因为 VPN 能力多依赖真机）
- 连接 VPN 后确认 command.sock 可被 CommandClient 连接（Status/Groups 任意一个能连上即可）

回滚点：若出现启动崩溃或 VPN 无法连接，回退到原先 `.onAppear` 初始化方式。

### Phase 2：把 MeshFluxMac 的 VPN Core（Controller + Clients）迁移进 iOS

目标：
- iOS 的 VPN 控制路径与 Mac 对齐：同一套 `VPNController` 负责 start/stop/status/reload/urltest 等。
- iOS 的 CommandClient 逻辑与 Mac 一致：包含稳定性与内存安全优化（深拷贝、tag 校验、避免跨线程误用 Go 对象）。

动作：
1. 将 `openmesh-apple/MeshFluxMac/core/VPNController.swift` 迁移/改写为 iOS 可用版本：
   - 去掉 AppKit 依赖（NSApplication/NSAlert）
   - 保留关键行为：notification-driven 状态更新、`reconnectToApplySettings()`、`requestExtensionReload()` 等
2. 迁移 `GroupCommandClient` 的稳定性优化到 iOS：
   - 引入 `stableInput(...)` 深拷贝
   - 引入 `validateTag(...)`（保守 ASCII 校验）
   - 对 urltest/selectOutbound 优先走“已连接 client + 专用 send queue”，fallback 到 standalone client
3. 增补 iOS 缺失的 VPN 功能客户端：
   - `LogCommandClient`（用于 Logs 页面）
   - `ConnectionCommandClient.closeConnection(...)`（如 UI 需要）
4. 统一 VPN Profile 的识别方式：
   - 不要只靠 `localizedDescription == "MeshFlux VPN"`（容易与 Variant/applicationName 漂移）
   - 推荐优先用 `providerBundleIdentifier == Variant.extensionBundleIdentifier` 找到 manager；必要时同时兼容旧 description
5. 将 Mac 的 **configNonce** 策略引入 iOS manager 创建/保存路径：
   - 在 `NETunnelProviderProtocol.providerConfiguration` 写入 `meshflux_config_nonce` 与 build 号，确保 preference 一定更新

验证：
- iOS 侧：用新 `VPNController` 连接/断开成功，且 UI 状态随系统通知变化
- iOS 侧：Groups/Connections/Status/log 能稳定刷新（无随机崩溃、无“数据乱码/空指针”）

回滚点：保留一条旧 VPN 连接路径（feature flag 或临时保留旧 view）以便快速切回。

### Phase 3：把 MeshFluxMac 的 VPN UI 信息架构迁移到 iOS（保留区块链 Tab）

目标：
- iOS 的 VPN UI 与 Mac 的页面语义一致（Dashboard/Profiles/Groups/Connections/Logs/Settings）
- iOS 的 “流量市场（区块链）” 保持原样可用

动作（推荐做法：先“能跑”，再“美观”）：
1. iOS 新增一个 `VPNMainView`，以 `NavigationPage` 为数据源组织页面：
   - 可直接复用 `openmesh-apple/MeshFluxMac/views/NavigationPage.swift` 的枚举结构，但要移除 macOS-only 依赖（例如 `Color(nsColor:)`）
2. 逐页迁移：
   - Dashboard：从 `openmesh-apple/MeshFluxMac/views/DashboardView.swift` 迁移，iPhone 上改为 2 列网格或纵向卡片
   - Profiles：迁移 `ProfilesView`/`EditProfileView`/`ImportProfileView`/`NewProfileView`，复用 `VPNLibrary/ProfileManager`
   - Groups：迁移 `GroupsView`（依赖 `GroupCommandClient`）
   - Connections：迁移 `ConnectionsView`/`ConnectionDetailsView`（依赖 `ConnectionCommandClient`）
   - Logs：按 `AppConfig.showLogsInUI` 控制是否显示入口；iOS 先默认隐藏，稳定后开放
   - Settings：迁移 `openmesh-apple/MeshFluxMac/views/SettingsView.swift` 的 VPN 设置逻辑（本地网络、APNs、enforceRoutes 等），并保留 iOS 特有说明
3. 替换旧 iOS VPN 页面：
   - 删除或下线 `HomeTabView`、`SettingsTabView` 中与 VPN 强耦合的 UI
   - `MainTabView` 中把 Tab1 改为 `VPNMainView`；Tab2 继续 `MeTabView`；Tab3 可指向新的 Settings 或保留现有设置再逐步迁移

验证：
- iOS：进入 VPN Tab → 能连接/断开 → Dashboard 状态刷新
- iOS：Profiles 可创建/导入/切换；切换后 VPN 能按新 profile 生效（必要时调用 `reconnectToApplySettings()`）
- iOS：Groups 可 urltest、可切换 selector；Connections 可查看/关闭
- iOS：切到“流量市场”Tab，钱包相关功能不受影响

回滚点：若 UI 迁移导致大面积回归，可暂时保留旧 Home/Settings 的 VPN UI（仅做导航切换）直至新 UI 稳定。

### Phase 4：对齐（可选）iOS Extension 与 Mac 的“优化点”

> 这部分属于“功能稳定性/一致性增强”，建议在 iOS App 侧迁移完成后再做，避免一次性改动过大。

建议对齐项：
1. **reloadService 顺序**（参考 macOS extension）：
   - reload 前：`close old` → `commandServer.setService(nil)` → `newService.start()` → `setService(newService)`
2. **stopTunnel 清理网络设置**：
   - 在 stopTunnel 里先 `setTunnelNetworkSettings(nil)`，降低残留路由带来的后续异常
3. **provider message 的 urltest（可选）**：
   - 若希望复用 Mac 的“app 不传 groupTag、extension 自动选组并回传 delay”机制，可在 iOS extension 加上 `"action":"urltest"` 支持

验证：
- iOS：频繁切换 profile/重连情况下不出现 service 卡死
- iOS：多次连接/断开后不出现“无法成为 primary route”类问题（如遇到，可在日志中观测）
- iOS：urltest provider message（若实现）能返回 delays 并刷新 UI

回滚点：Extension 改动应单独提交/可单独回退；保持 App 侧仍可用 command.sock 方案。

---

## 5. 风险清单与应对

- **iOS 与 macOS 的系统行为差异**：iOS 不适合沿用“主程序退出 extension 自动停 VPN”的心跳策略（iOS 前后台/进程管理更激进，可能误停）。
  - 应对：iOS 先不引入 heartbeat stop；仅保留 macOS。
- **Swift↔GoMobile 内存/生命周期问题**：从 Go 迭代器拿到的字符串/对象可能在异步/跨线程使用时触发崩溃或乱码。
  - 应对：迁移 Mac 的 `stableInput`/`validateTag`；UI 层只持有 Swift 深拷贝后的值；不要跨线程保留 Go iterator。
- **NETunnelProviderManager 的 preference 更新不生效**：签名/entitlement 变更后系统沿用旧配置导致 extension 启动失败。
  - 应对：引入 configNonce 写入 `providerConfiguration`，确保 `saveToPreferences` 真正写入并触发系统更新。
- **Bundle ID / localizedDescription 漂移**：iOS 当前用 `"MeshFlux VPN"`，而 `VPNLibrary/Variant.applicationName` 在 iOS 为 `"OpenMesh"`。
  - 应对：用 providerBundleIdentifier 做 primary 匹配，并兼容旧 description 迁移；最终收敛到一个稳定命名。

---

## 6. 验收标准（最终交付）

1. MeshFluxIos：区块链（钱包/PIN/余额/x402）功能与界面完全可用（无回归）。
2. MeshFluxIos：VPN 功能与界面以 MeshFluxMac 为基准迁移完成：
   - Dashboard/Profiles/Groups/Connections/(可选 Logs)/Settings 页面可用
   - 连接/断开稳定；profile 切换可生效；groups/connection/status 数据可靠刷新
3. 代码结构清晰：
   - VPN Core 与 UI 分层；共享逻辑尽量复用（VPNLibrary/SharedCode），平台差异用条件编译或抽象隔离

---

## 7. 构建与测试（建议命令）

> VPN 功能强依赖真机与签名/entitlement，命令行 build 仅用于“快速验证能编译”；功能验证仍以 Xcode 连接真机为准。

- 列出 scheme（确认 scheme 名称）：`xcodebuild -list -project openmesh-apple/MeshFlux.xcodeproj`
- 构建 iOS App（仅编译）：`xcodebuild -project openmesh-apple/MeshFlux.xcodeproj -scheme MeshFluxIos -configuration Debug -sdk iphonesimulator build`
- 构建 iOS Extension（仅编译）：`xcodebuild -project openmesh-apple/MeshFlux.xcodeproj -scheme vpn_extension_ios -configuration Debug -sdk iphonesimulator build`
- 构建 macOS App（仅编译）：`xcodebuild -project openmesh-apple/MeshFlux.xcodeproj -scheme MeshFluxMac -configuration Debug -sdk macosx build`
