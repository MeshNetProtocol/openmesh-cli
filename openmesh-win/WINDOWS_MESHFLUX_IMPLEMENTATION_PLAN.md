# OpenMesh Windows 实施总计划（对齐 MeshFluxMac）

## 1. 目标与范围

### 1.1 目标

在 `openmesh-win` 下实现一个 Windows 托盘应用，功能与 `openmesh-apple/MeshFluxMac + vpn_extension_macos` 对齐，包含：

- VPN 启停与状态管理
- 基于 profile 的配置加载与热重载
- 动态规则（`routing_rules.json`）注入
- 出站节点 URLTest 与节点切换（select outbound）
- 连接/流量/分组状态展示
- 托盘菜单主入口 + 弹窗式管理界面
- 钱包/余额/x402 能力对齐 `go-cli-lib/interface`

### 1.2 非目标（第一阶段不做）

- 100% 复刻 SwiftUI 动画细节（先做视觉和交互等价）
- 一次性做全量市场后端改造（先兼容现有 profile/provider 文件结构）
- 直接在 WinForms 内嵌 GoMobile 动态库（复杂度和稳定性风险高）

## 2. 现状分析（基于当前代码）

### 2.1 `openmesh-apple/vpn_extension_macos` 的核心能力

参考：

- `openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift`
- `openmesh-apple/vpn_extension_macos/LibboxSupport.swift`
- `openmesh-apple/vpn_extension_macos/DynamicRoutingRules.swift`
- `openmesh-apple/vpn_extension_macos/Info.plist`
- `openmesh-apple/vpn_extension_macos/vpn_extension_macos.entitlements`

已实现并需要在 Windows 对齐的关键点：

- 生命周期：`startTunnel` / `stopTunnel` / `sleep` / `wake`
- 启动顺序：`Setup -> CommandServer.start -> NewService -> Service.start -> setService`
- 配置入口：严格按 selected profile 读取，不走隐式 fallback
- 配置补丁：动态规则注入、routing mode patch、includeAllNetworks 兼容性校验
- IPC 消息：`reload`、`urltest`、`select_outbound`
- 命令面：状态/分组/连接（通过 command client）
- 心跳自杀：主程序心跳丢失 3 次后主动停隧道
- tun 打开与系统网络设置编排（IPv4/IPv6 route、DNS、Proxy）

观察到的实现特征（Windows 也建议保留）：

- 服务启动和重载都在专用串行队列，避免竞态
- 配置解析采用“宽松 JSON（去注释、去尾逗号）”策略，兼容配置来源差异
- 与 UI 的交互尽量通过 JSON action，避免 UI 直接持有底层对象

### 2.2 `go-cli-lib` 的核心能力

参考：

- `go-cli-lib/interface/wallet.go`
- `go-cli-lib/interface/app_lib.go`
- `go-cli-lib/interface/vpn.go`
- `go-cli-lib/interface/vpn_darwin.go`
- `go-cli-lib/interface/vpn_ios.go`
- `go-cli-lib/interface/vpn_android.go`
- `go-cli-lib/go.mod`

已实现可复用能力：

- 钱包：生成助记词、BIP44 派生、keystore 加解密
- 链上余额：USDC（Base 主网/测试网）
- x402 支付

现状缺口：

- VPN 对外 API 在 `interface` 层基本是占位逻辑（iOS/Android）或演示级逻辑（darwin）
- 尚无 `windows` build-tag 的 VPN 实现文件
- 但依赖已包含 Windows 相关组件（`wintun`、`wireguard/windows`、`go-winio`），说明技术路线可行

## 3. 架构结论（Windows 对等设计）

## 3.1 进程模型（对齐“主 App + 扩展”）

建议采用三层：

- `OpenMeshWin.exe`（WinForms 托盘 UI，用户态）
- `openmesh-win-core.exe`（Go 核心进程，负责 sing-box/libbox、配置、命令）
- `openmesh-win-service.exe`（Windows Service 外壳，可选但强烈建议，用于提权和开机常驻）

理由：

- 对齐 macOS 的“主程序 + 扩展”隔离模型
- VPN/TUN/路由操作在 Windows 通常需要更高权限
- UI 崩溃不应导致隧道核心立即退出

## 3.2 通信模型

- UI <-> Core：Named Pipe JSON-RPC（本机）
- Service <-> Core：进程控制 + 健康检查（或同一进程）
- 保持 action 协议和苹果侧一致，优先复用：
  - `reload`
  - `urltest`
  - `select_outbound`
  - 补充 Windows 必要 action：`start_vpn`、`stop_vpn`、`status`、`groups`、`connections`

## 3.3 目录与数据模型（对齐 FilePath）

建议：

- 共享目录：`%ProgramData%\OpenMesh\shared`
- 工作目录：`%ProgramData%\OpenMesh\work`
- 缓存目录：`%ProgramData%\OpenMesh\cache`
- 配置目录：`%ProgramData%\OpenMesh\configs`
- Provider 目录：`%ProgramData%\OpenMesh\MeshFlux\providers\<provider_id>\`
- 心跳文件：`%ProgramData%\OpenMesh\MeshFlux\app_heartbeat`

这样可以直接复用苹果侧的 provider/rules 文件组织方式。

## 4. 功能映射（Apple -> Windows）

| Apple 组件 | 当前职责 | Windows 对应 |
|---|---|---|
| `PacketTunnelProvider` | VPN 生命周期 + 配置解析 + IPC action | `openmesh-win-core` 的 `TunnelController` + `ActionServer` |
| `LibboxSupport` | Tun 打开、网络参数、默认接口监控 | `WinTunAdapter` + `RouteManager` + `DnsManager` |
| `DynamicRoutingRules` | 读取/规范化规则并注入 route.rules | `rules` 包（Go）复刻同逻辑 |
| `AppHeartbeatWriter` + extension heartbeat check | 主程序存活协同 | UI 写心跳，Core 读心跳并自停 |
| `StatusCommandClient/GroupCommandClient/ConnectionCommandClient` | 菜单界面实时数据源 | WinForms `CoreClient`（Pipe 订阅） |
| `MenuBarExtra` UI | 托盘入口、节点管理、流量视图 | NotifyIcon + 主弹窗 Form + 浮动子窗体 |
| `go-cli-lib/interface/wallet.go` | 钱包/余额/x402 | 直接在 Core 进程复用 |

## 5. 核心模块设计（Windows）

## 5.1 Go Core（建议放在 `go-cli-lib/cmd/openmesh-win-core`）

模块拆分建议：

- `internal/core/bootstrap.go`
- `internal/core/tunnel_controller.go`
- `internal/core/config_resolver.go`
- `internal/core/config_patch.go`
- `internal/core/routing_rules.go`
- `internal/core/action_server_pipe.go`
- `internal/core/status_stream.go`
- `internal/core/heartbeat_guard.go`
- `internal/wallet/service.go`（复用 `interface/wallet.go`）

关键行为：

- 启动顺序严格串行，重载路径和苹果侧一致
- `resolveConfig` 流水线：
  - 读 selected profile
  - provider 规则注入（`routing_rules.json`）
  - 应用 routing mode patch（保留 raw profile 语义）
  - 校验 tun 参数兼容性
- action 兼容苹果侧 payload，便于未来统一控制面

## 5.2 Windows VPN 子系统

优先路线：

- 采用 sing-box 的 `tun` inbound + `wintun`
- Go Core 统一管理：
  - 虚拟网卡建立/释放
  - 路由注入/回滚
  - DNS 设置/回滚
  - 可选系统代理开关

需要明确的工程事实：

- 首次安装/驱动阶段需要管理员权限
- 若使用 Windows Service，核心进程权限和回滚能力更稳定

## 5.3 WinForms 托盘应用

组件建议：

- `TrayBootstrap`：NotifyIcon、右键菜单、生命周期
- `MainPanelForm`：托盘主弹窗（对齐 macOS 菜单窗）
- `NodePickerForm`：节点详情和选择
- `TrafficForm`：流量图和累计值
- `CoreClient`：Pipe RPC + 订阅
- `StateStore`：UI 状态归一化（连接态、当前 profile、分组、节点）

视觉/交互对齐点（来自 MeshFluxMac）：

- 图标状态：`mesh_on`/`mesh_off`
- 主入口宽度和密度接近（mac 约 420x520）
- 顶部三 tab：Dashboard / Market / Settings
- 蓝青色渐变背景 + 玻璃卡片 + 状态色（绿/黄/红）
- 提供独立弹窗：节点详情、流量详情

## 5.4 钱包与支付

复用 `go-cli-lib/interface/wallet.go` 的方法：

- `GenerateMnemonic12`
- `CreateEvmWallet`
- `DecryptEvmWallet`
- `GetTokenBalance`
- `MakeX402Payment`

安全落地：

- keystore 文件仅存密文
- UI 输入密码不落盘
- 可选接入 DPAPI 做二次保护

## 6. 分阶段实施计划（完整）

## Phase 0：基线与目录重构（1-2 天）

交付：

- 在 `openmesh-win` 建立清晰结构（UI/文档）
- 在 `go-cli-lib` 新建 `cmd/openmesh-win-core` 骨架
- 明确配置目录规范和常量定义

验收：

- 工程能同时编译 C# UI 与 Go Core skeleton

## Phase 1：Core 最小可运行（3-4 天）

交付：

- Pipe server 建立
- `start_vpn` / `stop_vpn` / `status` action 打通
- Core 单线程生命周期控制器

验收：

- UI 可通过 Pipe 控制 Core 启停，并得到状态回包

## Phase 2：配置加载与补丁链路（4-5 天）

交付：

- Profile 读取
- `routing_rules.json` 解析与注入（对齐 `DynamicRoutingRules.swift`）
- routing mode patch（对齐 `ConfigModePatch.swift`）
- 配置宽松解析（注释/尾逗号）

验收：

- 给定 profile + provider rules，生成期望的运行配置 JSON
- 重载后规则无重复注入

## Phase 3：动作协议对齐（3-4 天）

交付：

- `reload` action
- `urltest` action
- `select_outbound` action
- 输入校验（tag 长度、字符、空值）

验收：

- 与苹果侧 action payload 兼容
- 节点切换在运行态可生效

## Phase 4：实时状态通道（4-6 天）

交付：

- 状态流：连接态、流量、内存、协程
- 分组流：outbound groups + items + selected
- 连接流：连接列表、筛选、排序、关闭连接

验收：

- UI 能实时渲染三类数据，断连可自动恢复订阅

## Phase 5：WinForms 托盘界面（5-7 天）

交付：

- NotifyIcon + 托盘菜单（Open/Connect/Disconnect/Exit）
- 主弹窗三 tab（Dashboard/Market/Settings）
- 节点窗口、流量窗口
- 风格与 MeshFluxMac 主视觉对齐

验收：

- 完整交互闭环：连接、测速、切节点、查看流量、修改设置

## Phase 6：钱包与 x402 集成（3-4 天）

交付：

- Core 暴露钱包相关 action
- UI 增加最小入口（可先放 Settings 或独立窗口）

验收：

- 助记词生成、钱包创建/解密、余额查询、x402 调用全部通

## Phase 7：安装与系统集成（5-7 天）

交付：

- 安装包（建议 WiX）
- Core/Service 自启动策略
- Wintun 依赖部署
- 卸载回滚（路由、DNS、服务）

验收：

- 新机器安装后可一键连接
- 卸载后无残留网络配置污染

## Phase 8：稳定性与发布（5-7 天）

交付：

- 崩溃恢复、日志轮转、心跳守护
- 端到端回归用例
- 发布候选版本（RC）

验收：

- 连续运行 24h 无资源泄漏
- 断网/重连/睡眠唤醒等场景可恢复

## 7. 测试计划

## 7.1 单元测试（Go）

- `routing_rules` 解析（json/simple/rules 三种形态）
- 配置注入去重正确性
- action 输入校验
- 钱包/支付核心逻辑回归

## 7.2 集成测试（Go + Windows）

- start/stop/reload 顺序稳定性
- URLTest + select_outbound 回路
- route/DNS 注入与回滚
- 心跳失联自动停隧道

## 7.3 UI 自动化/半自动回归

- 托盘菜单关键路径
- 连接态切换视觉反馈
- 节点选择后状态一致性
- 异常弹窗与错误提示

## 7.4 验收场景（必须通过）

- 首次安装 -> 连接成功
- 切换 profile -> reload 生效
- 切换节点 -> 出口变化可观测
- 关闭主窗体后程序驻留托盘
- 从托盘退出后 Core 优雅停止

## 8. 关键风险与对策

## 8.1 驱动与权限风险

- 风险：Wintun/路由操作需要管理员权限
- 对策：Service 模式托底；安装时权限校验；失败回滚脚本

## 8.2 Core 与 UI 进程解耦不足

- 风险：UI 崩溃导致隧道异常
- 对策：Core 独立进程 + 心跳约束，协议化通信

## 8.3 配置源不规范

- 风险：配置含注释、尾逗号导致 JSON 解析失败
- 对策：复刻苹果侧宽松解析策略并加测试

## 8.4 连接流/分组流竞态

- 风险：重连时订阅错乱或状态旧值覆盖
- 对策：统一状态版本号；重连后全量快照 + 增量流

## 8.5 安全风险（私钥/支付）

- 风险：敏感信息泄露
- 对策：密文存储 + 进程内最短驻留 + 日志脱敏

## 9. 代码落地建议（目录）

建议新增（示例）：

- `go-cli-lib/cmd/openmesh-win-core/main.go`
- `go-cli-lib/internal/wincore/...`
- `openmesh-win/src/OpenMeshWin.CoreClient/...`
- `openmesh-win/src/OpenMeshWin.UI/...`
- `openmesh-win/docs/`（后续拆分子设计文档）

当前仓库你已经有：

- `openmesh-win/OpenMeshWin.csproj`
- `openmesh-win/openmesh-win.sln`

可在此基础上逐步重构，不影响现有 WinForms 启动能力。

## 10. 首次执行顺序（建议）

1. 先做 Phase 0 + Phase 1，尽快形成“可连通的 UI <-> Core”最小闭环。
2. 再做 Phase 2 + Phase 3，把行为对齐到苹果扩展（reload/urltest/select_outbound）。
3. Phase 4 以后再推 UI 风格、市场和钱包扩展，避免前期 UI 返工。

这条顺序能最快暴露 Windows 网络栈和权限问题，降低后期返工成本。

