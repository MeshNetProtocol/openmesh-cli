# MeshFluxMac → MeshFluxIos 界面与功能迁移任务描述

**目标**：在 MeshFluxIos 中复现 MeshFluxMac 的 VPN 相关界面与能力，使双端体验一致；同时保留 MeshFluxIos 现有钱包功能不变。

---

## 一、背景与范围

- **MeshFluxMac** 已具备：菜单栏下拉（VPN 开关、配置选择、设置入口、退出）、独立设置窗口（模式、本地网络、About）、以及通过 VPNLibrary 的配置与扩展管理。
- **MeshFluxIos** 当前：首页为 VPN 状态 + 连接按钮 + 路由模式选择；「我的」Tab 为钱包（地址、USDC、网络、x402、安全、重置等）。iOS 未设置页，且与 Mac 在「设置」与首页信息架构上不一致。
- **本任务**：只修改 **MeshFluxIos** 这一个 target，在 iOS 上复现 Mac 的 VPN 相关界面与能力；**不触碰 MeshFluxMac 的任何代码**（Mac 当前已测试可用、基本稳定，保持现状）；**不修改** MeshFluxIos 的钱包相关页面与功能（见下）。

---

## 二、任务项概览

| 序号 | 任务 | 说明 |
|------|------|------|
| 1 | 删除旧文档 | 删除 `docs/VPN_REFACTOR_WORK_PLAN.md`（已完成）。 |
| 2 | 新增「设置」界面 | 在 MeshFluxIos 中新增与 MeshFluxMac 设置页对应的设置界面。 |
| 3 | 改造首页 | 调整 MeshFluxIos 首页，使其在 UI 与功能上对应 MeshFluxMac 的下拉菜单内容（含配置选择）。 |
| 4 | 多 Profile 支持 | MeshFluxMac 当前支持多 Profile（配置列表、选择）；MeshFluxIos 本次迁移中支持多 Profile，与 Mac 对齐。 |
| 5 | Extension 对齐 | 确保 iOS VPN extension 从 SharedPreferences 读取「模式」「本地网络」等，与 Mac 行为一致。 |
| 6 | 保留钱包 | 全程不修改 MeTabView 及 auth 相关界面与逻辑（钱包为 iOS 独有，不改动）。 |

以下对 2、3、4、5 做具体描述。

---

## 三、任务 2：新增「设置」界面

- **参考**：`MeshFluxMac/views/SettingsView.swift`。
- **内容**（仅列出与 Mac 对齐且适用于 iOS 的部分）：
  - **Packet Tunnel**
    - **模式**：二选一「按规则分流」/「全局」，对应 `SharedPreferences.includeAllNetworks`（false/true）。
    - **本地网络不走 VPN**：开关，对应 `SharedPreferences.excludeLocalNetworks`。
    - 若 VPN 已连接，切换上述项时需与 Mac 一致：先断开再重连以应用设置（可带“正在应用设置…”的 loading 与不可操作态）。
  - **About**
    - 文档链接、源码链接（与 Mac 相同 URL）。
- **不实现**：Mac 上的「Start At Login」等仅 macOS 才有的项。
- **入口**：从首页（或主导航）提供「设置」入口，进入该设置页。

---

## 四、任务 3：改造首页（对应 Mac 下拉菜单）

- **参考**：MeshFluxMac 菜单栏下拉中的 **VPN Tab**（`MenuBarWindowContent` 的 `vpnTabContent`）。
- **Mac 下拉当前包含**：
  - 应用名 + 版本号（OMLibboxVersion 或 CFBundleShortVersionString）
  - VPN 开关（已连接/未连接/连接中）
  - 配置选择（Profile 列表 + Picker）
  - 「设置」按钮（打开设置窗口）
  - 「退出」按钮
- **iOS 首页目标**：
  - 展示 **应用名 + 版本号**（与 Mac 同一套规则）。
  - 保留并强化 **VPN 开关**（连接/断开），状态与 Mac 一致（已连接/未连接/连接中）。
  - **配置**：MeshFluxMac 已支持多 Profile（配置列表 + Picker）；MeshFluxIos 首页同样支持配置列表与选择，与 Mac 一致（见四.1 多 Profile 支持）。
  - 明确 **「设置」入口**（跳转到上述新建设置页）。
  - **「退出」**：iOS 上通常不结束进程，可不做或仅做说明；若产品需要可后续再加。
- **约束**：首页仅做上述与 Mac 下拉对应的内容整合，不改变「我的」Tab 的钱包功能与结构。

---

## 四.1 任务 4：多 Profile 支持

- **现状**：MeshFluxMac 已支持多 Profile（ProfileManager、配置列表、选中项持久化 SharedPreferences.selectedProfileID、切换后已连接则重连等）。
- **目标**：MeshFluxIos 在本次迁移中支持多 Profile，与 Mac 对齐。包括：
  - 接入 VPNLibrary 的 ProfileManager、SharedPreferences（selectedProfileID）；
  - 首页提供配置列表与选择（Picker 或等价 UI），切换逻辑与 Mac 一致（若已连接则重连以应用新配置）；
  - 必要时与 Mac 一致的默认配置/安装逻辑（如首次安装默认配置），可参考 MeshFluxMac 的 DefaultProfileHelper 与 ensureDefaultProfileIfNeeded。
- **范围**：仅 VPN 配置的列表与选择，不涉及钱包；与「改造首页」配合实现。

---

## 五、任务 5：Extension 行为对齐

- **现状**：`vpn_extension_ios` 已使用 VPNLibrary（SharedPreferences、ProfileManager）拉取配置；但 `LibboxSupport` 中 `includeAllNetworks()` 目前写死为 `false`，未读 SharedPreferences。
- **目标**：
  - iOS App 在设置页修改「模式」「本地网络」时，写入 `SharedPreferences.includeAllNetworks` 与 `SharedPreferences.excludeLocalNetworks`（与 Mac 一致）。
  - `vpn_extension_ios` 在需要读「是否全局」「是否排除本地网络」的地方，从 SharedPreferences（或 NETunnelProviderProtocol 上由 App 注入的对应项）读取，与 `vpn_extension_macos` 行为一致。
- **结果**：用户在 iOS 设置页的修改能真实影响 extension 的路由/排除行为，与 Mac 一致。

---

## 六、不在此次任务内（边界说明）

- **不碰 MeshFluxMac**：本次任务**只修改 MeshFluxIos 这个 target**。**不修改、不触碰 MeshFluxMac 的任何代码**；MeshFluxMac 目前测试可用、基本稳定，保持现状。
- **不碰 MeshFluxIos 的钱包**：钱包是 MeshFluxIos 有而 MeshFluxMac 没有的功能。本次所有修改**不得改动** MeshFluxIos 的钱包相关页面和功能（如 MeTabView、auth 下的导入/新建/PIN、USDC、网络选择、x402、重置等），保持现有逻辑与 UI 不变。
- **多 Profile**：MeshFluxMac 当前已支持多 Profile（配置列表、选择），因此本次迁移中 MeshFluxIos **会支持**多 Profile，与 Mac 对齐；不属于「不做的内容」。

---

## 七、验收预期

1. **设置**：iOS 有独立设置页，包含「模式」「本地网络不走 VPN」和 About；修改后 extension 行为与 Mac 一致。
2. **首页**：iOS 首页具备与 Mac 下拉等价的：版本、VPN 开关、配置列表/Picker（多 Profile）、「设置」入口。
3. **钱包**：MeTabView 及 auth 相关流程与改动前一致，未被修改。
4. **Extension**：iOS extension 的全局/规则与本地网络排除逻辑由 SharedPreferences（或等价机制）驱动，与 Mac 对齐。
5. **多 Profile**：MeshFluxIos 支持配置列表与选择，行为与 MeshFluxMac 一致；MeshFluxMac 代码未被修改。

---

*文档创建后，再讨论具体实现步骤与拆分子任务。*
