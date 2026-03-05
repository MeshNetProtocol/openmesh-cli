# OpenMesh Android 与 iOS VPN Extension 功能对齐计划

## 1. 目标与范围

目标：让 `openmesh-android` 在 VPN 核心能力上与 `openmesh-apple/vpn_extension_ios` 达到行为一致（同一 profile 配置驱动、同一命令语义、同一可观测性标准），并在必要处扩展 `go-cli-lib` 作为 Android 侧可复用接口层。

对齐范围：
- VPN 生命周期：start / stop / reload。
- 配置来源：严格 profile 驱动（profile-only）。
- 运行期命令：`urltest`、`select_outbound`、`update_rules`、`reload`。
- 路由规则：provider 维度规则文件 + 热更新。
- 运行诊断：日志、状态、runtime diag。
- 网络底层：`VpnService` + libbox 平台接口对齐。

非本期范围：
- 与 iOS 完全一致的 UI 视觉（本计划聚焦功能与架构对齐）。
- Play 商店发布流程与商业化功能。

## 2. 对齐基线（代码来源）

iOS 基线（必须对齐）：
- `D:\worker\openmesh-cli\openmesh-apple\vpn_extension_ios\PacketTunnelProvider.swift`
- `D:\worker\openmesh-cli\openmesh-apple\vpn_extension_ios\LibboxSupport.swift`
- `D:\worker\openmesh-cli\openmesh-apple\vpn_extension_ios\DynamicRoutingRules.swift`
- `D:\worker\openmesh-cli\openmesh-apple\VPNLibrary\Network\ExtensionProfile.swift`

Android 技术参考（实现方式优先复用）：
- `D:\worker\openmesh-cli\sing-box\clients\android\app\src\main\java\io\nekohasekai\sfa\bg\VPNService.kt`
- `D:\worker\openmesh-cli\sing-box\clients\android\app\src\main\java\io\nekohasekai\sfa\bg\BoxService.kt`
- `D:\worker\openmesh-cli\sing-box\clients\android\app\src\main\java\io\nekohasekai\sfa\bg\PlatformInterfaceWrapper.kt`
- `D:\worker\openmesh-cli\sing-box\clients\android\app\src\main\java\io\nekohasekai\sfa\utils\CommandClient.kt`

Go 接口扩展位点：
- `D:\worker\openmesh-cli\go-cli-lib\interface\vpn_android.go`（当前为占位实现）
- `D:\worker\openmesh-cli\go-cli-lib\interface\vpn_types.go`
- `D:\worker\openmesh-cli\go-cli-lib\Makefile`（Android AAR 目标当前使用 `$(PKG)`，需修正为可用包变量）

## 3. 当前差距结论

`openmesh-android` 当前状态是工程壳：仅基础 Activity 与资源，未具备 VPN 服务层、配置层、命令层、规则热更新与诊断体系。

关键差距：
1. 无 Android `VpnService` / 前台服务 / binder 通道。
2. 无 libbox 平台接口封装（openTun、接口监听、DNS/代理状态）。
3. 无 profile 管理与持久化（selected profile、provider 绑定、运行态共享存储）。
4. 无 iOS 同语义命令接口（reload/urltest/select_outbound/update_rules）。
5. `go-cli-lib` Android VPN 接口为 stub，无法作为上层稳定接口。

## 4. 目标架构（openmesh-android）

建议在 `openmesh-android/app/src/main/java/com/meshnetprotocol/android` 下拆分：
- `vpn/`：`OpenMeshVpnService`、`OpenMeshBoxService`、`ServiceBinder`、`ServiceNotification`。
- `vpn/platform/`：`PlatformInterfaceAdapter`（对齐 `PlatformInterfaceWrapper` 行为）。
- `vpn/command/`：`CommandBridge`（封装 status/group/log/urltest/select）。
- `data/profile/`：Profile 存储、选中 profile、provider 映射。
- `data/rules/`：provider 规则文件读写、校验、原子替换。
- `diag/`：runtime diag 输出、stderr 归档、关键状态埋点。
- `ui/`：最小可用控制台（连接、断开、测速、切换节点、更新规则）。

## 5. 功能对齐矩阵

| iOS 能力 | Android 对齐方案 | 里程碑 |
|---|---|---|
| startTunnel/stopTunnel 生命周期 | `OpenMeshVpnService` + `OpenMeshBoxService`，前台服务+状态机 | Phase 1 |
| profile-only 配置解析 | 启动前强校验 selectedProfile + profile 文件可读 | Phase 1 |
| reload（服务热重载） | `serviceReload()` 重建 libbox service，不杀进程 | Phase 2 |
| urltest（可选 group） | 命令客户端订阅 group 状态并返回延迟快照 | Phase 2 |
| select_outbound | 透传到 standalone command client，参数校验 | Phase 2 |
| update_rules | provider 规则文件原子写入 + 触发 reload | Phase 3 |
| 文件监听触发 reload | 监听 providers 目录变更并 debounce reload | Phase 3 |
| runtime diag | 输出 `vpn_runtime_diag.json` + stderr 关键行 | Phase 4 |
| system proxy status | 与 Android `VpnService` 中 HTTP proxy 状态联动 | Phase 4 |
| 内存与稳定性观测 | 周期内存打点 + ANR/崩溃路径归档 | Phase 4 |

## 6. 分阶段执行计划

### Phase 0：基础设施与脚手架（1-2 天）
- 引入/确认 Android VPN 所需 manifest 权限、service、receiver、notification channel。
- 建立模块目录（vpn、data、diag、command）。
- 明确 App 内部状态机：`Stopped -> Starting -> Started -> Stopping`。

验收标准：
- 工程可编译。
- 服务可启动到 `Starting`，并有可见前台通知。

### Phase 1：核心 VPN 启停与配置对齐（3-5 天）
- 实现 `OpenMeshVpnService.openTun()`（参考 `sing-box` Android 客户端）。
- 实现 `OpenMeshBoxService.startService()/stopService()`。
- 接入 profile-only 配置读取；无 profile 时明确报错并中止启动。
- 打通 start/stop 与 UI 控制入口。

验收标准：
- 真机可建立 VPN 隧道。
- 选中 profile 后可稳定启动；无 profile 必然失败且错误可见。

### Phase 2：命令面与节点能力对齐（3-4 天）
- 建立命令桥：`reload`、`urltest`、`select_outbound`。
- 对齐 iOS 参数和响应语义（`ok/error` 风格）。
- 接入 groups/status/log 订阅能力。

验收标准：
- UI 可触发测速并得到延迟映射。
- 可在运行中切换 group 的 outbound。
- reload 后连接不中断或可控重建。

### Phase 3：规则文件与热更新（2-3 天）
- 实现 provider 规则文件路径与持久化策略（与 iOS provider 语义一致）。
- 实现 `update_rules`（JSON 校验、原子写入、自动 reload）。
- 增加文件监听 + debounce 机制。

验收标准：
- 更新规则后 1s 内触发 reload。
- 错误规则不会污染现有有效配置（回滚或拒绝写入）。

### Phase 4：诊断、代理与稳定性（2-4 天）
- 输出 `vpn_runtime_diag.json`（profile/provider/route/dns 摘要）。
- 关键日志与 stderr 归档策略。
- 补齐 system proxy status 读取与开关联动。
- 增加内存打点和故障注入测试（空 profile、无权限、规则损坏）。

验收标准：
- 出现故障时可通过日志/diag 快速定位。
- 长时间运行无明显泄漏或服务异常重启风暴。

### Phase 5：回归、发布与文档（2 天）
- 端到端回归（启动、切换节点、测速、规则更新、重连、开机后恢复）。
- 输出运维手册与故障排查清单。
- 形成版本发布清单。

验收标准：
- 回归用例通过率 >= 95%。
- 发布文档可独立指导测试和运维。

## 7. go-cli-lib 扩展计划（Android）

### 7.1 现状
- `vpn_android.go` 当前是占位实现，返回固定值，无法支撑生产逻辑。

### 7.2 改造目标
- 将 `go-cli-lib/interface` 升级为“跨端统一的控制接口层”：
  - 提供与 Android 服务层可对接的稳定 API（状态、命令、诊断）。
  - 保持 gomobile 友好（基础类型 + JSON 字符串参数/返回）。

### 7.3 建议新增接口（方向）
- `GetVpnStatusJSON() (string, error)`：统一返回连接状态和流量统计。
- `ExecuteVpnCommandJSON(command string, payload string) (string, error)`：承载 `reload/urltest/select_outbound/update_rules`。
- `ValidateProfileConfig(config string) (string, error)`：启动前配置校验。
- `BuildRuntimeDiagJSON(config string, profileMeta string) (string, error)`：统一诊断摘要格式。

### 7.4 构建链路任务
- 修复 `go-cli-lib/Makefile` 的 Android 目标变量（当前 `$(PKG)` 与实际不一致）。
- 在 CI 中增加 Android AAR 构建检查。
- 输出 AAR 接入 `openmesh-android` 的版本化流程（本地依赖/制品库二选一）。

## 8. 关键风险与应对

1. Android 系统版本碎片导致 VPN 行为差异。
- 应对：按 API level 分支处理路由与权限；最小支持版本先收敛到稳定区间。

2. profile 配置不规范导致启动失败率高。
- 应对：启动前做 JSON/字段校验，错误可视化并阻断启动。

3. 规则热更新与服务重载竞争。
- 应对：单线程 service 队列 + debounce + 原子写文件。

4. go-cli-lib 接口演进影响 iOS 现有调用。
- 应对：新增 API 不破坏旧 API，分阶段替换并保留兼容层。

## 9. 里程碑与交付物

- M1（Phase 0-1）：Android 可稳定连接 VPN，profile-only 生效。
- M2（Phase 2）：命令面与 iOS 语义对齐（reload/urltest/select_outbound）。
- M3（Phase 3-4）：规则热更新、runtime diag、稳定性指标到位。
- M4（Phase 5）：完整回归 + 发布文档。

交付物：
- `openmesh-android` 完整 VPN 可运行版本。
- `go-cli-lib` Android 接口增强版本 + AAR 构建流程。
- 对齐测试清单、故障排查文档、发布清单。

---

计划版本：v1（基于 2026-03-05 仓库现状）
