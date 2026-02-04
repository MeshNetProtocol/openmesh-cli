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
| L2 | Extension 读 SharedPreferences | ✅ vpn_extension_ios 在需要「是否全局」「是否排除本地网络」处从 SharedPreferences 读取（PacketTunnelProvider 与 LibboxSupport.includeAllNetworks/excludeLocalNetworks），与 vpn_extension_macos 一致。 |
| L3 | 首次安装默认配置 | ✅ iOS 首次启动或进入设置且配置列表为空时，从 bundle 的 default_profile.json 安装「默认配置」并设为选中；逻辑在 VPNLibrary.DefaultProfileHelper，与 Mac 一致。 |
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

## 四、L2：Extension 读 SharedPreferences（行为对齐）✅

- **实现**：`vpn_extension_ios` 已从 SharedPreferences 读取「是否全局」「是否排除本地网络」：
  - **PacketTunnelProvider**：`buildConfigContent()` 中读取 `SharedPreferences.includeAllNetworks`、`SharedPreferences.excludeLocalNetworks`，用于 route.final 与日志。
  - **LibboxSupport**：`includeAllNetworks()`、`excludeLocalNetworks()` 均返回 `SharedPreferences.*.getBlocking()`；`openTun` 中打日志使用 `excludeLocalNetworks()`。
- **结果**：在设置（或 Home）修改模式/本地网络后，extension 路由行为与 Mac 一致。

### iOS 全局模式与路由（split routes）

- **现象**：真机系统日志会出现 `NESMVPNSession: failed to add an IPv4 route` / `failed to add an IPv6 route`，导致全局模式下流量未进隧道、表现“无效”。
- **原因**：iOS 对单条默认路由（0.0.0.0/0、::/0）的安装常会拒绝；`includeAllNetworks` 仅影响协议层，隧道侧仍需能成功安装路由。
- **实现**：在 `vpn_extension_ios/LibboxSupport.swift` 中，当未从 libbox 拿到显式路由时，使用**分段默认路由**（与 sing-box Apple 客户端一致）：IPv4 使用 1.0.0.0/8、2.0.0.0/7、…、128.0.0.0/1；IPv6 使用 100::/8、200::/7、…、8000::/1，等价于 0.0.0.0/0 与 ::/0，但系统会接受。
- **协议层**：`includeAllNetworks` 需在**启动隧道前**写入并保存到 `NETunnelProviderManager`（App 在 `ensureMeshFluxManagerExists` / 设置应用时已做），否则系统不会按“包含所有网络”处理。

### 全局模式 route.final 与 geoip rule-set（对齐 vpn_extension_macos / vpn_extension_macx / SFI）

- **route.final**：与 **vpn_extension_macos** 一致，在 `resolveConfigContent()` 后对内容做 `patchRouteFinalForGlobalMode`：当 `SharedPreferences.includeAllNetworks` 为 true 时，将 config 中 `route.final` 设为 `"proxy"`（profile 驱动与 legacy 路径均会经过该补丁）。
- **geoip-cn rule-set**（与 SFM 一致）：
  - **vpn_extension_macos**、**vpn_extension_ios**：不做 geoip patch，config 保留 remote rule-set（`download_detour: "proxy"`），由 **libbox 在 service 启动时**通过 proxy 出站拉取，与 SFM 行为一致。
  - **vpn_extension_macx**：System Extension 沙箱内联网受限，仍对 config 做 patch：将远程 geoip-cn 替换为 bundle 内 `geoip-cn.srs`（构建前脚本 `scripts/download_geoip_cn.sh` 写入 `vpn_extension_macx/Resources/`），若无则移除该 rule-set 及 `route_exclude_address_set` 引用。

### 测试 geoip（libbox 拉取）与控制台日志

- **是否需要删配置**：不需要删除系统 VPN 配置。若希望「干净」状态、观察 libbox 是否重新拉取 rule-set，可只删 **App Group 工作目录**（如 `~/Library/Group Containers/group.com.meshnetprotocol.OpenMesh/` 下的 `Library/Caches`、`Working` 等），不必动系统设置里的 VPN。
- **控制台可关注的日志**（进程选 MeshFlux 或对应 extension）：
  - `MeshFlux VPN extension using profile-driven config (id=..., name=...)` 或 `using bundled default_profile.json`：说明走的是 profile/默认配置。
  - `MeshFlux VPN extension: passing config to libbox (no geoip patch; remote rule-set geoip-cn will be fetched by libbox). stderr.log: <path>`：确认未做 geoip patch，config 带 remote rule-set，由 libbox 拉取；同时给出 libbox 的 stderr 路径。
  - `MeshFlux VPN extension box service started`：libbox 已启动；若前面拉取 geoip 成功，会在这之前完成。
- **libbox 内部日志**（拉取/加载 rule-set、错误）：在 **stderr.log** 里，路径即上面日志里的 `<path>`；Mac 上也可在应用「日志」页通过「刷新」读该文件。

---

## 五、L3：首次安装默认配置 ✅

- **实现**：
  - **VPNLibrary** 新增 **DefaultProfileHelper**：`installDefaultProfileFromBundle()`（列表为空时从 bundle 的 default_profile.json 创建「默认配置」并设为选中）、`ensureDefaultProfileIfNeeded()`（空则安装，非空则修复 selectedProfileID）。
  - **MeshFluxIos**：将 **default_profile.json** 加入 App 的 Copy Bundle Resources（与 Mac 共用同一文件）；在 **OpenMeshApp.onAppear** 调用 `DefaultProfileHelper.ensureDefaultProfileIfNeeded()`；在 **SettingsTabView.loadProfiles()** 当列表为空时先调用 `ensureDefaultProfileIfNeeded()` 再重新拉取列表。
  - **MeshFluxMac**：DefaultProfileHelper 改为委托 VPNLibrary.DefaultProfileHelper，保留 cfPrefsTrace。
- **结果**：首次安装或清空数据后，用户无需手动添加配置即可在设置 Tab 看到并使用默认配置。

---

## 六、边界说明

- **不碰 MeshFluxMac**：仅修改 MeshFluxIos、vpn_extension_ios 及共享层（如 VPNLibrary）中与 iOS 相关的必要部分。
- **不碰钱包**：流量市场、auth（导入/新建/PIN、USDC、x402、重置等）的界面与逻辑保持不变。

---

## 七、验收预期（界面已完成，逻辑待 L1–L3）

1. **界面**：✅ 三 Tab（Home、流量市场、设置）；设置 Tab 含版本、VPN、配置、Packet Tunnel、About。
2. **L1**：Home 规则/全局与设置 Tab 模式共用 SharedPreferences.includeAllNetworks，两处一致。
3. **L2**：✅ vpn_extension_ios 从 SharedPreferences 读模式与本地网络，与 Mac 一致。
4. **L3**：✅ 首次安装或配置为空时自动安装默认配置，设置 Tab 可选中使用。
5. **钱包**：流量市场与 auth 能力不变；底层已接 Go，无桩逻辑。

---

## 八、后续功能：Dashboard 统计、出站组、连接、配置列表

参考 **SFI**（`sing-box/clients/apple/SFI` + `ApplicationLibrary/Views`）与 **MeshFluxMac** 已有实现（`StatusCommandClient`、`GroupCommandClient`、`ConnectionCommandClient`），以下功能通过连接 extension 的 **command.sock**（App Group）获取数据，**可实现**。

### 8.1 优先级与放置

| 功能 | 优先级 | 放置位置 | 说明 |
|------|--------|----------|------|
| **出站组** | **P0 最高** | Home Tab 内（主内容或显眼入口） | 用户必须能看到哪个节点好用、可切换节点；参考 SFI GroupListView / GroupView / GroupItemView，Mac 已有 GroupCommandClient。 |
| **Dashboard 统计卡片** | P1 | Home Tab（仅连接数 + 流量） | 不实现内存、协程（Mac/iOS 差异）；仅展示「连接数」（入站/出站）和「流量」（实时 + 合计）。数据来自 StatusCommandClient ↔ command.sock；若 extension 支持 trafficAvailable 则展示。 |
| **连接** | P2 | Home 子页面 | 用户有兴趣可点进查看；参考 SFI ConnectionListView。ConnectionCommandClient 已用于 Mac，iOS 可复用逻辑。 |
| **配置列表** | 已有 | 设置 Tab | 当前为配置 Picker；保持放在设置 Tab，若需完整「配置列表」页（增删改、导入）可再扩展。 |

### 8.2 实现可行性（参考 SFI + Mac）

- **连接数、流量**：SFI 的 `ExtensionStatusView` 使用 `CommandClient(.status)`，收到 `LibboxStatusMessage`（connectionsIn/Out、uplink/downlink、uplinkTotal/downlinkTotal、trafficAvailable）。Mac 已实现 `StatusCommandClient` + `ExtensionStatusBlock`。iOS 扩展与 Mac 扩展同源（libbox），**可做**：在 Home 仅渲染「连接数」「流量」两张卡片，VPN 连接时 `StatusCommandClient.connect()`，断开时 `disconnect()`。
- **出站组**：SFI 的 `GroupListView` 使用 `CommandClient(.groups)`，收到出站组列表（tag、type、selected、selectable、items 含 urlTestDelay）；`GroupItemView` 通过 `LibboxNewStandaloneCommandClient()!.selectOutbound(groupTag, outboundTag)` 切换节点，通过 `urlTest(groupTag)` 测速。Mac 已有 `GroupCommandClient`（含 urlTest、selectOutbound、setSelected）。**必须实现**：在 iOS Home 加入出站组列表与节点选择/测速 UI。
- **连接**：SFI 的 `ConnectionListView` 使用 `CommandClient(.connections)`，收到 `LibboxConnection` 列表；支持筛选（全部/活动中/已关闭）、排序、关闭全部。Mac 已有 `ConnectionCommandClient`。**可做**：在 Home 增加「连接」入口，进入子页面展示列表（可选实现）。

### 8.3 技术要点

- **CommandClient 与 socket**：主 App 通过 **OpenMeshGo** 的 `OMLibboxNewCommandClient` / `OMLibboxNewStandaloneCommandClient` 连接 extension 在 App Group 下创建的 **command.sock**（与 Mac 一致）。iOS 主 App 已链接 OpenMeshGo，仅需在 MeshFluxIos 内加入 Status/Group/Connection 的 Client 与 UI。
- **仅当 VPN 已连接时**：extension 才会创建 command.sock，故 Status/Group/Connection 的 connect 应在「已连接」后调用，断开后 disconnect。
- **出站组**：需在 Home 展示组列表 → 每组展示节点列表（tag、类型、延迟、当前选中勾选）→ 支持点击切换节点、点击闪电测速；逻辑与 Mac / SFI 一致。

### 8.4 实现顺序与当前状态

1. **出站组（P0）** ✅：MeshFluxIos 已新增 `GroupCommandClient` + `OutboundGroupSectionView`（出站组列表、节点选择、测速、展开/收起），放在 Home Tab，仅 VPN 连接时显示。
2. **Dashboard 统计（P1）** ✅：已新增 `StatusCommandClient` + `StatusCardsView`（仅「连接数」「流量」「流量合计」），VPN 连接时显示于 Home。
3. **连接（P2）** ✅：已新增 `ConnectionCommandClient` + `ConnectionListView`（筛选、排序、关闭全部），从 Home 的「连接」按钮以 sheet 打开。
4. **配置列表**：维持当前设置 Tab 的配置 Picker；若需完整列表页再扩展。

---

*L1、L2、L3 已完成；八 中 出站组、Dashboard 统计、连接 已实现。*
