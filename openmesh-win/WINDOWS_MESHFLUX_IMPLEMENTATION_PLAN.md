# OpenMesh Windows 生产等效开发计划（对齐 openmesh-apple）

更新时间：2026-02-24
适用目录：`D:\worker\openmesh-cli\openmesh-win`

---

## 0. 执行进展（验收驱动）

- [x] P0 基线冻结（已验收通过，2026-02-23）
  - 基线文档：`openmesh-win/docs/P0_BASELINE.md`
  - Mock/Real 判定：`openmesh-win/docs/P0_MOCK_REAL_CRITERIA.md`
  - 验收脚本：`openmesh-win/tests/Run-P0-Baseline.ps1`
- [x] P1 Go Core 骨架接入（已验收通过，2026-02-23）
  - Go Core 骨架：`go-cli-lib/cmd/openmesh-win-core/main.go`
  - 双栈模式：`AppSettings.CoreMode = mock|go`
  - 验收脚本：`openmesh-win/tests/Build-P1-GoCore.ps1`、`openmesh-win/tests/Run-P1-GoCore-Smoke.ps1`
- [x] P2 配置与规则链路真实化（已验收通过，2026-02-23）
  - 宽松 JSON + 动态规则解析（json/text）
  - `reload/urltest/select_outbound` 兼容与选择持久化
  - 验收脚本：`openmesh-win/tests/Run-P2-GoCore-Rules.ps1`
- [x] P3 真实隧道能力接入（已验收通过，2026-02-23）
  - 已验收：P3 第二轮（网络框架 + 引擎生命周期）
  - 已验收：P3 第三轮（引擎健康探测与失败回滚，`p3_engine_health`）
  - 验收脚本：`openmesh-win/tests/Run-P3-GoCore-Network-Framework.ps1`、`openmesh-win/tests/Run-P3-GoCore-Engine-Mode.ps1`、`openmesh-win/tests/Run-P3-GoCore-Engine-Health.ps1`
- [x] P4 命令与状态流对齐（已验收通过，2026-02-23）
  - 已验收：P4 第一轮（`status_stream` 基础通道 + C# 流式读取接口），2026-02-23
  - 已验收：P4 第二轮（UI 流式优先 + 断线重连 + 轮询兜底），2026-02-23
  - 已验收：P4 第三轮（核心重启后的流式重连验证脚本与流程固化），2026-02-23
  - 已验收：P4 第四轮（Connection 实时推送：`connections`/`close_connection`/`connections_stream`），2026-02-23
  - 已验收：P4 第五轮（UI 连接列表切换为 `connections_stream`），2026-02-23
  - 已验收：P4 第六轮（Group 实时推送：`groups_stream` 与验收脚本），2026-02-23
  - 已验收：P4 第七轮（UI 节点分组切换为 `groups_stream`），2026-02-23
  - 说明文档：`openmesh-win/docs/P4_STATUS_STREAM_FOUNDATION.md`、`openmesh-win/docs/P4_UI_STREAM_RECONNECT.md`、`openmesh-win/docs/P4_STREAM_RECONNECT_ACCEPTANCE.md`、`openmesh-win/docs/P4_CONNECTION_STREAM.md`、`openmesh-win/docs/P4_UI_CONNECTION_STREAM_RECONNECT.md`、`openmesh-win/docs/P4_GROUP_STREAM.md`、`openmesh-win/docs/P4_UI_GROUP_STREAM_RECONNECT.md`
  - 验收脚本：`openmesh-win/tests/Run-P4-GoCore-Status-Stream.ps1`、`openmesh-win/tests/Run-P4-GoCore-Stream-Reconnect.ps1`、`openmesh-win/tests/Run-P4-GoCore-Connections-Stream.ps1`、`openmesh-win/tests/Run-P4-GoCore-Groups-Stream.ps1`
- [x] P5 钱包与 x402 真实集成（已验收通过，2026-02-24）
  - 已验收：P5 第一轮（Go Core 钱包/x402 动作闭环：`wallet_generate_mnemonic/create/unlock/balance/x402_pay`），2026-02-24
  - 已验收：P5 第二轮（`go-cli-lib/interface/wallet.go` 桥接 + keystoreJson 持久化 + `x402_pay` 严格真实模式验证与离线回退），2026-02-24
  - 已验收：P5 第三轮（Settings -> Go Core 环境变量链路：`OPENMESH_WIN_P5_BALANCE_REAL/STRICT` 与 `OPENMESH_WIN_P5_X402_REAL/STRICT`），2026-02-24
  - 已验收：P5 第四轮（钱包响应模式可观测性：`walletBalanceSource`、`paymentMode` + UI 日志透出 + 模式验收脚本），2026-02-24
  - 说明文档：`openmesh-win/docs/P5_GO_CORE_WALLET_BRIDGE.md`
  - 验收脚本：`openmesh-win/tests/Run-P5-GoCore-Wallet-Smoke.ps1`、`openmesh-win/tests/Run-P5-GoCore-Wallet-Bridge.ps1`、`openmesh-win/tests/Run-P5-GoCore-Wallet-Modes.ps1`
- [ ] P6 服务化与安装器正式化（进行中）
  - 已验收：P6 第一轮（发布前置检查脚本：构建链、WiX、签名工具、证书、Wintun），2026-02-24
  - 已验收：P6 第二轮（WiX MSI 打包脚本：支持 WiX v4/v3 探测与生成），2026-02-24
  - 已验收：P6 第三轮（真实 WiX 环境构建验证 + MSI 产物结构与元数据检查），2026-02-24
  - 已验收：P6 第四轮（openmesh-win-service 骨架接入 + 安装包链路纳管 + 预检覆盖），2026-02-24
  - 已验收：P6 第五轮（SCM 服务注册/卸载脚本接入安装链路 + 管理员门禁验收），2026-02-24
  - 已验收：P6 第六轮（SCM 严格验收模式：RequireAdmin + AutoElevate 一键提权），2026-02-24
  - 已验收：P6 第七轮（安装链路 Wintun 依赖门禁：RequireWintun + AutoCopyWintun），2026-02-24
  - 已验收：P6 第八轮（打包链路 Wintun 门禁：Build-Package 支持 RequireWintun + AutoCopyWintun），2026-02-24
  - 已验收：P6 第九轮（MSI 链路 Wintun 门禁透传：Build-P6-Wix-Msi -> Build-Package），2026-02-24
  - 已验收：P6 第十轮（统一 MSI Wintun 验收：`Run-P6-Wix-Msi-Wintun-Guard.ps1`），2026-02-24
  - 已验收：P6 第十一轮（主验收脚本并入 Wintun 参数：`Run-P6-Wix-Msi-Smoke/Validate`），2026-02-24
  - 已验收：P6 第十二轮（发布预检增强：`Run-P6-Release-Preflight.ps1` 支持 `-FailOnWarn` 严格门禁与 `-WriteJsonReport` 结构化报告），2026-02-24
  - 已验收：P6 第十三轮（发布预检 Wintun 显式门禁：`Run-P6-Release-Preflight.ps1` 支持 `-RequireWintun` 与 `-WintunPath`，并支持 `OPENMESH_WIN_WINTUN_DLL`），2026-02-24
  - 已验收：P6 第十四轮（发布预检管理员门禁：`Run-P6-Release-Preflight.ps1` 支持 `-RequireAdmin` 与 `-AutoElevate`），2026-02-24
  - 已验收：P6 第十五轮（发布预检一键门禁：`Run-P6-Release-Preflight.ps1` 支持 `-ReleaseGate`，自动启用 `RequireAdmin/RequireWintun/FailOnWarn/WriteJsonReport`），2026-02-24
  - 已验收：P6 第十六轮（发布预检可选执行 SCM 严格验收：`Run-P6-Release-Preflight.ps1` 支持 `-RunScmStrict` 并纳入 FAIL/PASS 结果），2026-02-24
  - 已验收：P6 第十七轮（发布预检提权等待增强：`Run-P6-Release-Preflight.ps1` 支持 `-AutoElevateTimeoutSeconds`，输出提权进度心跳并在超时后自动失败），2026-02-24
  - 已验收：P6 第十八轮（发布预检最新报告指针：自动刷新 `p6-release-preflight-latest.txt/.json`，便于快速读取最近结果），2026-02-24
  - 已验收：P6 第十九轮（发布预检快速查看模式：`Run-P6-Release-Preflight.ps1` 支持 `-ShowLatest`，直接输出 `latest` 报告与汇总），2026-02-24
  - 已验收：P6 第二十轮（发布预检 latest 新鲜度门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestMaxAgeMinutes`，在 `-ShowLatest` 模式下可判定报告是否过期），2026-02-24
  - 已验收：P6 第二十一轮（发布预检 latest 摘要模式：`Run-P6-Release-Preflight.ps1` 支持 `-ShowLatestSummaryOnly`，只输出最近报告摘要），2026-02-24
  - 已验收：P6 第二十二轮（发布预检 latest 过期自动刷新：`Run-P6-Release-Preflight.ps1` 支持 `-RefreshLatestOnStale`，可选 `-RefreshLatestSkipBuild/-RefreshLatestSkipGoCoreBuild`），2026-02-24
  - 已验收：P6 第二十三轮（发布预检 latest 严格摘要门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestRequireNoFail` 与 `-LatestFailOnWarn`），2026-02-24
  - 已验收：P6 第二十四轮（发布预检 latest 文本/JSON 一致性门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestRequireTextJsonConsistent`），2026-02-24
  - 已验收：P6 第二十五轮（发布预检 latest 同批次门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestRequireSameGeneratedAtUtc`），2026-02-24
  - 已验收：P6 第二十六轮（发布预检 latest WARN 白名单门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestIgnoreWarnChecks`，可与 `-LatestFailOnWarn` 联动），2026-02-24
  - 已验收：P6 第二十七轮（发布预检 latest 指定检查项 PASS 门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestRequirePassChecks`），2026-02-24
  - 已验收：P6 第二十八轮（发布预检 latest 期望计数门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestExpectedFailCount/-LatestExpectedWarnCount/-LatestExpectedPassCount`），2026-02-24
  - 本轮完成（待验收）：P6 第二十九轮（发布预检 latest 检查项级别门禁：`Run-P6-Release-Preflight.ps1` 支持 `-LatestRequireCheckLevels`，格式 `check=PASS|WARN|FAIL`）
  - 说明文档：`openmesh-win/docs/P6_RELEASE_PREFLIGHT.md`、`openmesh-win/docs/P6_WIX_MSI_PIPELINE.md`、`openmesh-win/docs/P6_WIX_MSI_VALIDATION.md`、`openmesh-win/docs/P6_SERVICE_SCAFFOLD.md`、`openmesh-win/tests/P6_SERVICE_SCM.md`、`openmesh-win/tests/P6_WINTUN_DEP_GUARD.md`、`openmesh-win/tests/P6_WIX_MSI_WINTUN_GUARD.md`
  - 验收脚本：`openmesh-win/tests/Run-P6-Release-Preflight.ps1`、`openmesh-win/tests/Run-P6-Wix-Msi-Smoke.ps1`、`openmesh-win/tests/Run-P6-Wix-Msi-Validate.ps1`、`openmesh-win/tests/Run-P6-Service-Scaffold.ps1`、`openmesh-win/tests/Run-P6-Service-SCM.ps1`、`openmesh-win/tests/Run-P6-Service-SCM-Strict.ps1`、`openmesh-win/tests/Run-P6-Wintun-Guard.ps1`、`openmesh-win/tests/Run-P6-Wix-Msi-Wintun-Guard.ps1`

---

## 1. 文档目标

本计划用于把当前 `openmesh-win` 的“可运行演示版（MVP/Mock）”逐步升级为“生产等效版本（与 `openmesh-apple` 真正对齐）”。

这里的“生产等效”指：

- 使用真实隧道/路由能力（非模拟流量与模拟连接）
- 与 `openmesh-apple/vpn_extension_macos` 在动作协议与行为上对齐（`reload/urltest/select_outbound/...`）
- 与 `go-cli-lib` 的钱包/x402 真实能力打通（非本地模拟扣减）
- 提供可安装、可回滚、可升级、可观测的 Windows 发布链路

---

## 2. 当前代码基线（As-Is）

### 2.1 已有成果（可复用）

`openmesh-win` 当前已经具备：

- WinForms 托盘应用与多 Tab 主界面
- C# `CoreClient` + NamedPipe 协议
- `OpenMeshWin.Core`（.NET）动作闭环：
  - `reload` / `urltest` / `select_outbound`
  - `status` / `connections` / `close_connection`
  - 钱包/x402 入口动作（当前为本地模拟逻辑）
- 设置持久化、启动项集成、心跳文件、日志轮转、自动恢复框架
- 安装/卸载/打包脚本与 RC 产物脚本

### 2.2 与生产等效的主要差距（Gap）

1. **核心引擎差距**
   - 当前 Core 仍是 .NET 模拟实现，不是 `go-cli-lib + sing-box/wintun` 真实引擎。

2. **网络能力差距**
   - 未真正接管系统流量；连接统计/流量数据主要是模拟数据。

3. **命令流差距**
   - 与 Apple 侧 command client 的实时推送语义尚未等效（目前以轮询 + 快照为主）。

4. **钱包/x402 差距**
   - 当前为本地演示钱包与支付逻辑，不是 `go-cli-lib/interface/wallet.go` 的真实链路。

5. **发布链路差距**
   - 当前是脚本安装链路，尚未形成正式 MSI/WiX/签名/升级回滚标准链路。

---

## 3. 目标架构（To-Be）

推荐架构（与 Apple 的“主 App + extension”思想对齐）：

- `OpenMeshWin.exe`（UI）
  - 托盘、设置、节点操作、钱包操作、状态展示
- `openmesh-win-core.exe`（Go，真实核心）
  - sing-box/wintun、配置解析、动态规则注入、动作处理、状态流
- `openmesh-win-service.exe`（可选但建议）
  - 管理员权限操作、系统启动、恢复与守护
- IPC
  - UI <-> Core：Named Pipe（先兼容现协议，再扩展为流式事件）

> 说明：
> 为了稳定性与隔离，优先采用“Go Core 独立进程”路线；
> 不优先把整个核心编译成 C# 直调 DLL（`c-shared`）模式。

---

## 4. 路线决策（正式）

### 4.1 Go 集成路线

采用 **Route-B（推荐）**：

- `go-cli-lib/cmd/openmesh-win-core` 新建真实核心进程
- C# 侧通过 Pipe 调用 Go Core（不是调用 .NET mock core）

暂不采用 **Route-A（整体 c-shared）** 作为主线，原因：

- 调试/崩溃隔离差
- 版本兼容与内存边界复杂
- 与当前 Apple extension 的“进程隔离”理念不一致

> 可选补充：仅钱包模块未来可评估 `c-shared`，但主隧道能力保持独立进程。

### 4.2 兼容迁移策略

分两层迁移，避免一次性重写：

- 第一步：保留现有 UI 与协议模型，新增 `CoreMode = mock|go` 开关
- 第二步：默认切换到 `go`，`mock` 仅保留开发与应急诊断用途

---

## 5. 分阶段实施计划（生产等效版）

## Phase P0：冻结当前基线（1 天）

目标：保护现有可运行能力，防止后续迁移期回退。

任务：

- 记录当前 MVP 行为基线与 demo 验收脚本
- 将 `.NET mock core` 明确标注为 `legacy/mock`
- 在文档中定义“Mock 功能”与“真实功能”判定口径

DoD：

- 可以一键启动当前版本并通过现有 Phase8 回归脚本

---

## Phase P1：Go Core 骨架接入（2-4 天）

目标：UI 可无感切换到 Go Core。

任务：

- 新建 `go-cli-lib/cmd/openmesh-win-core`（或 `go-cli-lib/cmd/openmesh-win-core-real`）
- 实现 Pipe server（先最小动作）：`ping/status/start_vpn/stop_vpn/reload`
- C# `CoreProcessManager` 支持选择启动 Go Core
- 加入 `CoreMode` 配置（appsettings）

DoD：

- `CoreMode=go` 下，UI 基本连接控制可用
- `CoreMode=mock` 仍可运行（回退路径可用）

---

## Phase P2：配置与规则链路真实化（4-6 天）

目标：对齐 `PacketTunnelProvider.swift + DynamicRoutingRules.swift` 核心语义。

任务：

- 迁移/复刻以下逻辑到 Go Core：
  - 宽松 JSON 解析（注释/尾逗号）
  - 动态规则解析（simple/sing-box/text）
  - 规则注入去重
  - selector/urltest 默认出站持久化
- 兼容 `reload/urltest/select_outbound` payload

DoD：

- 给定 profile + routing_rules，可得到与 Apple 逻辑一致的 effective config
- 重复 reload 不出现规则重复注入

---

## Phase P3：真实隧道能力接入（7-12 天）

目标：替换模拟流量与连接为真实隧道数据。

任务：

- 接入 sing-box tun inbound + wintun
- 路由注入/回滚、DNS 注入/回滚
- 管理员权限探测与失败回退
- 停止/崩溃后的网络清理
- 引擎健康探测（进程存活 + 可选 TCP 端口探测）与启动失败回滚

DoD：

- 可真实连接并接管流量
- Stop/崩溃后路由、DNS 能回滚
- `status` 指标来自真实网络层

---

## Phase P4：命令与状态流对齐（5-8 天）

目标：对齐 Apple 侧 `StatusCommandClient/GroupCommandClient/ConnectionCommandClient` 语义。

任务：

- Core 输出流式状态通道（增量 + 快照）
- Group/Connection 实时推送
- UI 改造：从轮询为主切换到“事件流 + 断线重连”

DoD：

- UI 在连接/节点切换时稳定实时刷新
- Core 重启后 UI 自动重连并恢复状态

---

## Phase P5：钱包与 x402 真实集成（4-7 天）

目标：替换当前本地模拟钱包/x402。

任务：

- 直接接入 `go-cli-lib/interface/wallet.go`：
  - `GenerateMnemonic12`
  - `CreateEvmWallet`
  - `DecryptEvmWallet`
  - `GetTokenBalance`
  - `MakeX402Payment`
- 统一密钥与 keystore 管理策略（避免明文驻留）

DoD：

- 钱包创建/解锁/余额/x402 支付走真实接口
- 支付结果与错误码可追踪

---

## Phase P6：服务化与安装器正式化（6-10 天）

目标：可发布的 Windows 安装链路。

任务：

- 引入 `openmesh-win-service`（权限托管、开机自启、守护）
- WiX/MSIX 产物（替代纯脚本安装）
- 驱动/依赖检查（wintun）
- 升级与卸载回滚策略

DoD：

- 新机器安装后可一键连接
- 升级后配置可迁移
- 卸载后无网络污染残留

---

## Phase P7：稳定性与发布（7-10 天）

目标：达到 RC/GA 发布门槛。

任务：

- 24h 长稳测试（内存、句柄、CPU、连接恢复）
- 异常场景：断网、睡眠唤醒、Core 崩溃、权限变化
- 端到端回归矩阵 + 自动化脚本固化
- 发布清单：版本、签名、哈希、变更说明

DoD：

- RC 通过全部阻断项（P0）
- 可生成 GA 候选

---

## 6. 阻断项（Release Gates）

以下任一未通过，不得宣称“生产等效完成”：

- [ ] 真实 wintun/sing-box 接管成功且可回滚
- [ ] `reload/urltest/select_outbound` 行为与 Apple 对齐
- [ ] 实时 status/group/connection 非模拟
- [ ] 钱包/x402 走真实 go-cli-lib 能力
- [ ] 安装/升级/卸载链路完整（含回滚）
- [ ] 24h 稳定性测试通过

---

## 7. 目录级改造清单

### 7.1 `openmesh-win`（C#）

- 保留：UI、托盘、设置、日志、安装入口
- 新增：
  - `CoreMode` 切换与真实 Core 连接策略
  - 事件流消费器（替代纯轮询）
  - 生产诊断面板（日志/核心状态/版本）

### 7.2 `go-cli-lib`（Go）

- 新增：
  - `cmd/openmesh-win-core/`（生产核心进程）
  - `internal/wincore/`（配置/动作/状态/隧道）
- 复用：
  - `interface/wallet.go` 的真实钱包/x402能力

---

## 8. 测试策略（生产等效）

### 8.1 必测类别

- 单元测试：规则解析、配置注入、钱包输入校验
- 集成测试：UI<->Core、Core<->网络栈、安装升级卸载
- 稳定性：长时运行 + 异常注入

### 8.2 最低验收场景

- 首次安装 -> 连接 -> 切节点 -> 断网 -> 恢复
- 切 profile -> reload 生效 -> 无重复规则
- 支付失败/成功路径均可观测
- 卸载后网络清理完成

---

## 9. 风险与对策

- 风险：Windows 权限与驱动复杂
  - 对策：服务化承接高权限操作，严格回滚
- 风险：Go/C# 协议漂移
  - 对策：协议 schema 固化 + 回归脚本
- 风险：将模拟逻辑误当生产逻辑
  - 对策：每阶段 DoD 必须包含“真实数据来源”验证

---

## 10. 立即执行（Next 3）

1. 建立 `CoreMode` 双栈并把 UI 默认切到 `mock`（防止影响现用），同时可手动切 `go`。
2. 在 `go-cli-lib` 创建 `openmesh-win-core` 骨架，先跑通 `ping/status/start/stop/reload`。
3. 输出第一版“Go Core 对接报告”（动作兼容性 + 缺口清单 + 下一轮迭代任务）。

---

## 11. 里程碑定义

- M1：Go Core 可被 UI 驱动（P1 完成）
- M2：配置/规则/出站选择与 Apple 基本对齐（P2 完成）
- M3：真实隧道接管可用（P3 完成）
- M4：实时状态流对齐（P4 完成）
- M5：钱包/x402 真实化（P5 完成）
- M6：安装服务化可发布（P6 完成）
- M7：RC 达标并可签发（P7 完成）

