# MeshFluxMac → MeshFluxIos 界面与功能迁移任务描述

**目标**：在 MeshFluxIos 中复现 MeshFluxMac 的 VPN 相关界面与能力，使双端体验一致；同时保留并完善 MeshFluxIos 现有钱包功能。

---

## 〇、iOS 钱包实现状态（已完成）

iOS 钱包已接入 Go 库（`OpenMeshGo.xcframework`），界面功能均调用真实实现：

| 功能 | Go API | iOS 调用位置 | 状态 |
|------|--------|--------------|------|
| 生成助记词 | `GenerateMnemonic12` | `MnemonicDisplayView` → `GoEngine.generateMnemonic12()` | ✅ 已实现 |
| 创建钱包 | `CreateEvmWallet` | `PINFlowViews` → `GoEngine.createEvmWallet()` | ✅ 已实现 |
| 解密钱包 | `DecryptEvmWallet` | `GoEngine.decryptEvmWallet()`（协议 + Bridge） | ✅ 已实现 |
| 代币余额 | `GetTokenBalance` | `MeTabView` → `GoEngine.getTokenBalance()` | ✅ 已实现 |
| 支持网络列表 | `GetSupportedNetworks` | `GoEngine.getSupportedNetworks()`（网络选择当前为静态列表，可后续改为从 Go 拉取） | ✅ API 已实现 |
| VPN 状态 | `GetVpnStatus` | `HomeTabView` → `GoEngine.getVpnStatus()` | ✅ 已实现 |

- **实现方式**：`GoEngine.initLocked` 仅使用 `OMOpenmeshNewLib()`；成功则通过 `OpenmeshAppLibBridge` 调用 Go；失败则抛出错误（「无法加载核心库，请重新安装应用或联系支持」），不使用桩逻辑。
- **x402 支付**：Go 侧已有 `MakeX402Payment`；若 iOS 需要，可在协议与 GoEngine 中增加对应方法并在 UI 调用。

---

## 一、背景与范围

- **MeshFluxMac** 已具备：菜单栏下拉（VPN 开关、配置选择、设置入口、退出）、独立设置窗口（模式、本地网络、About）、以及通过 VPNLibrary 的配置与扩展管理。
- **本任务**：只修改 **MeshFluxIos** 与 **vpn_extension_ios**，在 iOS 上复现 Mac 的 VPN 相关能力；**不触碰 MeshFluxMac**；**不修改** MeshFluxIos 的钱包相关页面与功能（流量市场、auth 等）。

---

## 一.1、界面完成情况（当前结构）

iOS 界面已按与 Mac 对齐的方案调整完毕，**三 Tab 结构**如下：

| Tab | 内容 |
|-----|------|
| **Home** | 当前状态、一键 Connect/Disconnect、规则/全局切换（Routing Mode）。无设置按钮。 |
| **流量市场** | 原「我的」：钱包地址、USDC、网络选择、x402、安全、调试/重置。已移除「VPN 与系统设置」卡片。 |
| **设置** | 应用与版本、VPN 状态与连接按钮、配置列表与 Picker（多 Profile）、Packet Tunnel（模式、本地网络不走 VPN）、About（文档与源码链接）。 |

- **设置 Tab** 已使用 VPNLibrary（ProfileManager、SharedPreferences.selectedProfileID、includeAllNetworks、excludeLocalNetworks），切换模式/本地网络/配置时若 VPN 已连接会先断开再重连，并显示「正在应用设置…」。
- **VPN 隧道**：`vpn_extension_ios` 已补 `boxService.start()`，真机连接后应出现状态栏 VPN 图标。

**剩余工作 = 功能逻辑实现**（见下），不再做界面结构调整。

---

## 二、剩余任务：功能逻辑实现

以下为与 Mac 行为一致所需实现的**逻辑**，不改变现有界面结构。

| 序号 | 任务 | 说明 |
|------|------|------|
| L1 | 规则/全局数据源统一 | Home 的「规则/全局」与设置 Tab 的「模式」共用同一数据源（SharedPreferences.includeAllNetworks），避免双处不一致；Extension 只读该一份。 |
| L2 | Extension 读 SharedPreferences | vpn_extension_ios 在需要「是否全局」「是否排除本地网络」处从 SharedPreferences（或 App 注入的 provider 配置）读取，与 vpn_extension_macos 一致。 |
| L3 | 首次安装默认配置 | iOS 首次启动或配置列表为空时，安装默认配置（如从 default_profile.json 创建并设为选中），与 Mac 的 ensureDefaultProfileIfNeeded 行为一致。 |
| — | 保留钱包 | 不修改流量市场及 auth 相关逻辑。 |

以下对 L1、L2、L3 做具体描述。

---

## 三、L1：规则/全局数据源统一

- **现状**：Home 使用 `RoutingModeStore` 读写「规则/全局」；设置 Tab 使用 `SharedPreferences.includeAllNetworks`。两处可能不一致，且 Extension（L2）将只读 SharedPreferences。
- **目标**：
  - Home 的规则/全局切换改为读写 **SharedPreferences.includeAllNetworks**（与设置 Tab 共用同一存储），不再单独使用 RoutingModeStore 作为唯一来源。
  - 进入设置 Tab 或 Home 时，两处展示的「模式」一致。
- **可选**：若保留 RoutingModeStore 作为 UI 缓存，需在启动/前后台切换时与 SharedPreferences 同步；或直接弃用 RoutingModeStore，仅用 SharedPreferences。

---

## 四、L2：Extension 读 SharedPreferences（行为对齐）

- **现状**：`vpn_extension_ios` 已用 VPNLibrary 拉取配置（ProfileManager、selectedProfileID）；但「是否全局」「是否排除本地网络」在 LibboxSupport 等处可能仍为写死（如 `includeAllNetworks() == false`），未读 SharedPreferences。
- **目标**：
  - 在 extension 需要「全局模式」「排除本地网络」的地方，从 **SharedPreferences.includeAllNetworks**、**SharedPreferences.excludeLocalNetworks** 读取（或从 NETunnelProviderProtocol 中由 App 注入的配置读取），与 `vpn_extension_macos` 一致。
  - App 侧：设置 Tab 已写 SharedPreferences；若完成 L1，Home 的规则/全局也写同一份。
- **结果**：在设置（或 Home）修改模式/本地网络后，extension 路由行为与 Mac 一致。

---

## 五、L3：首次安装默认配置

- **现状**：Mac 在菜单首次出现时调用 ensureDefaultProfileIfNeeded，从 bundle 的 default_profile.json 创建「默认配置」并设为选中；iOS 设置 Tab 在配置列表为空时仅显示「暂无配置」。
- **目标**：
  - iOS 在适当时机（如 App 首次启动、或进入设置 Tab 且配置列表为空时）执行与 Mac 一致的默认配置安装逻辑：从 **default_profile.json**（需加入 iOS target 的 bundle）创建 Profile，写入 ProfileManager 并设为 **SharedPreferences.selectedProfileID**。
  - 可参考 MeshFluxMac 的 **DefaultProfileHelper.installDefaultProfileFromBundle** 与 **ensureDefaultProfileIfNeeded**；逻辑可放在共享层或 iOS 单独实现。
- **结果**：首次安装或清空数据后，用户无需手动添加配置即可在设置 Tab 看到并使用默认配置。

---

## 六、边界说明

- **不碰 MeshFluxMac**：仅修改 MeshFluxIos、vpn_extension_ios 及共享层（如 VPNLibrary）中与 iOS 相关的必要部分。
- **不碰钱包**：流量市场、auth（导入/新建/PIN、USDC、x402、重置等）的界面与逻辑保持不变。

---

## 七、验收预期（界面已完成，逻辑待 L1–L3）

1. **界面**：✅ 三 Tab（Home、流量市场、设置）；设置 Tab 含版本、VPN、配置、Packet Tunnel、About。
2. **L1**：Home 规则/全局与设置 Tab 模式共用 SharedPreferences.includeAllNetworks，两处一致。
3. **L2**：vpn_extension_ios 从 SharedPreferences 读模式与本地网络，与 Mac 一致。
4. **L3**：首次安装或配置为空时自动安装默认配置，设置 Tab 可选中使用。
5. **钱包**：流量市场与 auth 能力不变；底层已接 Go，无桩逻辑。

---

*剩余工作为 L1、L2、L3 的功能实现，可按顺序或并行推进。*
