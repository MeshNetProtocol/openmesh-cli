# MeshFluxMac 菜单栏宽窗口 UI 改造规格（UI-first / Functional migration plan）

更新时间：2026-02-06（持续迭代）  
适用 Target：`openmesh-apple/MeshFluxMac`  
范围：以 UI 为主推进；允许把“容易接入”的设置项直接实现（例如 Start at login），其余按本文档的迁移方案分阶段落地。  

---

## 0. 当前状态（给其他 AI 的快速入口）

目前菜单栏宽窗口已具备可用 UI 结构（含 DashBoard/Market/Settings 3 个 Tab、流量图表、节点切换窗口、左下角齿轮菜单），并已完成关键数据接入与稳定性修复。

已落地（✅）：
- DashBoard 流量：已接入 `StatusCommandClient`（实时速率 + 累计 uplinkTotal/downlinkTotal），图表与 More info 窗口会随连接态实时刷新。
- 节点列表：已实现“离线解析”（从当前 Profile 的 config JSON 提取节点 tag / server / port），未连接也能展示节点与选择；地区字段暂用 `-`。
- 节点选择持久化：按 profile 维度保存 `selectedOutboundTagByProfile`（SharedPreferences），支持离线可选、下次连接后复用。
- 连接态应用选择：菜单内不再直接调用 `selectOutbound`（避免崩溃）；改为“保存偏好 + 触发 extension reload”，由 extension 在 reload/start 时应用 selector 的 `default` 到偏好节点。
- 稳定性：切换节点崩溃已消失（根因是主进程内使用 GoMobile/OpenMeshGo 的 group/selector 链路导致 heap corruption，已从菜单节点链路移除）。

遗留（⚠️）：
- 离线（未连接）场景下菜单“测速”使用 **直连 TCP RTT 估算**（`NWConnection` connect ready 的耗时），与旧设置页「出站组」里的 libbox/urltest 语义不一致（只能当参考）。
- 连接态场景下菜单“测速”已通过 extension IPC 调用 libbox/urltest（PacketTunnelProvider 内执行 `urlTest`）对齐设置页语义；如果发现菜单与设置页结果仍不一致，需要继续排查“测速入口是否走到同一套 urltest 通道”。

---

## 1. 背景与目标

MeshFluxMac 是一个 **macOS 菜单栏应用**，主入口是菜单栏弹出的宽窗口（window style 的 MenuBarExtra）。  
当前“设置”入口会打开一个包含 **左侧栏 + 右侧内容** 的复杂 `NavigationSplitView` 窗口（类似传统桌面 App 的侧栏设置）。  

本次改造目标：

1. 将“用户常用、能在菜单栏宽窗口展示”的信息与操作集中到 **第 1 个 Tab（DashBoard）**。
2. 对于不适合塞进菜单窗口的内容，以 **“单页面窗口（single page window）”** 打开：每个入口打开一个独立页面，不再是左侧栏/多级导航的复杂设置。
3. UI 先行、功能分期迁移：先把布局/交互稳定，再逐步替换假数据并迁移旧窗口的功能。

---

## 2. 当前实现位置（代码导航）

菜单栏窗口主入口：
- `openmesh-apple/MeshFluxMac/OpenMeshMacApp.swift`：`MenuBarExtra` + `MenuBarWindowContent`

顶部 Tab（文字 + 下划线）：
- `openmesh-apple/MeshFluxMac/OpenMeshMacApp.swift`：`MenuTopTabBar` + `MenuBarTab`

当前第 1 个 Tab（DashBoard）的内容：
- `openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`：主卡片（VPN 开关/商户选择）、流量图表、节点+速率行、底部齿轮菜单

旧设置窗口（复杂左侧栏）：
- `OpenMeshMacApp.swift`：`SettingsWindowPresenter.show()` → `MenuContentView`（`NavigationSplitView`）
- `openmesh-apple/MeshFluxMac/views/NavigationPage.swift`：侧栏页面枚举与映射

节点切换窗口（单页）：
- `openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`

---

## 3. 需求与术语（对齐 UI 与旧功能）

### 3.1 节点（对应旧“出站组”）精简展示 + 测速

用户可理解的命名：
- UI 中不再使用“出站组”，改为“节点”（或同等更直观的词）

供应商相关命名（UI 术语）：
- 原「配置」标签改为「流量商户」
- 首次安装默认 Profile 名称从「默认配置」改为「官方供应商」

展示形式（菜单窗口内）：
- 展示“节点名称 + 上下行速率（↑/↓）+ 切换按钮”
- “切换”打开节点窗口：展示节点列表、地区、延迟、测速（全局/单条）

### 3.2 Dashboard 状态网格改造：只保留「流量（速率）」「流量合计（上下行曲线）」

放置位置：
- 在菜单窗口第 1 个 Tab（DashBoard）中展示

流量（即时速率）：
- 只用文字 + 数字，尽量“小而清晰”（例如：↑ 3.0 KB/s、↓ 5.5 KB/s）

流量合计（累计）：
- 需要重点设计：未来会加图标与趋势图，效果参考截图（两条折线的简图）
- 当前可用假数据：模拟折线图数据

交互：
- 提供 “More info” 按钮（本轮打开一个 **单页面窗口**，展示更大的图与假数据）

布局：
- 曲线图下方为“节点+速率”信息区（淡色背景区分图表）

### 3.3 菜单栏 3 个 Tab（当前命名）

当前 Tab 名称：
- 第 1 个：`DashBoard`
- 第 2 个：`Market`
- 第 3 个：`Settings`

说明：
- 第 2/3 个 Tab 目前仍为占位内容（敬请期待/假数据）

---

## 4. 已完成（代码现状 / 状态更新）

已完成（✅）：
1. 菜单栏宽窗口 + 顶部 Tab 样式（文字 + 下划线）
2. DashBoard Tab：VPN 控制 + 流量商户下拉 + 流量曲线图 + 节点+速率行（已接入真实 StatusCommandClient）
3. More info：单页面窗口（连接态实时刷新 uplinkTotal/downlinkTotal 图表与数值）
4. 节点切换：单页面窗口（离线解析节点列表；离线可选可回放；连接态通过 extension reload 应用选择）
5. 左下角齿轮菜单：Update（仅日志）、About、Source Code、Start at login（真实）、Preferences（打开旧窗口）
6. 默认 Profile 名称：新安装时创建 `官方供应商`（见 DefaultProfileHelper）
7. 默认选中节点（示例配置）：`meshflux150`
8. “本地网络不走 VPN”：不再提供关闭入口，保持默认 true（设置页会自动纠正为 true）

说明：
- 旧 `Preferences`（split-view）仍保留作为兜底入口，后续会按迁移计划逐步拆分为单页。

### 4.1 关键设计变更（节点切换与崩溃修复）

背景：在菜单节点切换路径中直接使用 `GroupCommandClient`/`selectOutbound` 时，多次出现 `outboundTag` 变为二进制垃圾字符串并触发 `swift_retain` 崩溃（疑似 GoMobile/OpenMeshGo 相关的 heap corruption）。  
现方案（稳定性优先）：
- 菜单节点列表与当前选中：以 Profile config JSON 的离线解析为“单一真相（offline source of truth）”。
- 选择节点：只写入 `SharedPreferences.selectedOutboundTagByProfile[profileID] = outboundTag`。
- 连接态应用：触发 `vpnController.requestExtensionReload()`；由 extension 在 reload/start 时读取偏好并修改 selector 的 `default`。
- 结果：切换节点不再崩溃，同时满足“离线可选可回放”。

### 4.2 本次实现涉及的关键文件（便于继续迭代）

- 菜单 DashBoard（流量 + 节点行 + 窗口管理）：`openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`
- 节点窗口（离线列表 + RTT 估算测速 + 选择/禁用/提示）：`openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`
- 偏好存储（按 profile 保存选择）：`openmesh-apple/VPNLibrary/Database/SharedPreferences.swift`
- extension 应用偏好（reload/start 时设置 selector default）：`openmesh-apple/vpn_extension_macx/PacketTunnelProvider.swift`
- 旧设置页「出站组」对照入口（仍基于 command.sock）：`openmesh-apple/MeshFluxMac/views/GroupsView.swift`

---

## 5. UI 已具备但尚未实现的功能清单（对应关系 + TODO）

下表用于“对齐 UI ↔ 旧功能 ↔ 代码入口”，方便其他 AI 直接接手：

| 当前 UI 元素 | 对应旧设置窗口功能 | 现有代码入口 | 现状 | 需要实现 |
|---|---|---|---|---|
| 流量曲线图（上下行） | Dashboard/ExtensionStatus 的流量展示（部分） | `openmesh-apple/MeshFluxMac/views/DashboardView.swift`（`StatusCommandClient` + `OMLibboxStatusMessage`） | 已接入真实数据（连接态实时） | （已完成） |
| “节点+速率”信息行 | 旧「出站组」+ 旧「流量」的组合 | 速率：`StatusCommandClient`；节点：Profile config JSON（离线解析） | 已可用（速率实时；节点可切换且不崩溃） | 节点延迟/测速语义对齐设置页 urltest（见第 6 节/第 10 节） |
| “切换”按钮 → 节点窗口 | 旧「出站组」页面（节点选择/测速） | 菜单节点：`MenuNodePickerWindowView.swift`（离线解析 + 直连 RTT）；旧设置页：`GroupsView.swift` + `GroupCommandClient` | 已可用（离线可选可回放；连接态通过 extension reload 应用选择） | ⚠️ 遗留：菜单“测速”与设置页不一致（见第 6 节/第 10 节） |
| 连接列表（Connections） | 旧「连接」页面 | `openmesh-apple/MeshFluxMac/views/ConnectionsView.swift` + `ConnectionCommandClient` | 计划舍弃 | 不迁移；如未来需要，以单窗口形式恢复 |
| Update 菜单项 | （新增）更新机制 | 左下角齿轮菜单 | 仅日志 | 后续接 Sparkle/自研更新；或先做“检查更新”占位弹窗 |
| Start at login 菜单项 | 旧 SettingsView 的 App 区 | `ServiceManagement.SMAppService.mainApp` | 已实现 | 仅 UI 微调/异常提示优化 |
| Preferences 菜单项 | 旧 split-view 设置窗口 | `SettingsWindowPresenter.show()` | 已实现 | 后续拆分为单页面窗口，逐步下线 split-view |

---

## 6. 后续功能迁移方案（重点：未连接 VPN 也要展示/测速节点）

### 6.1 关键约束（来自现有代码/架构）

当前 Mac 的“出站组/测速/切换”依赖 extension 的 `command.sock`：
- `GroupCommandClient` 注释明确：**仅当 VPN 已连接时可用**（未连接时 `command.sock` 不存在）。见 `openmesh-apple/MeshFluxMac/core/GroupCommandClient.swift`。
- `LogsView` 也有类似约束：仅 VPN 连接时才有实时流。见 `openmesh-apple/MeshFluxMac/views/LogsView.swift`。

因此：要做到“未连接 VPN 也能展示并测速”，必须新增一条 **不依赖 command.sock** 的数据/测速链路。

### 6.2 推荐分期（先可用，再逐步逼近“与出站组一致”的真实测速）

#### Phase A（低风险）：连接后接入真实 groups/status，替换假数据
1. ✅ 已完成：DashBoard Tab 已引入 `StatusCommandClient`，使用 `OMLibboxStatusMessage`：
   - 上下行速率：`uplink/downlink`
   - 流量合计曲线：`uplinkTotal/downlinkTotal`
2. ⚠️ 已调整：菜单节点切换路径不再引入 `GroupCommandClient.selectOutbound`。
   - 原因：在主进程内使用 GoMobile/OpenMeshGo 的 group/selector 链路会出现不稳定崩溃（heap corruption）。
   - 替代：菜单改为“保存偏好 + 触发 extension reload”，由 extension 在 reload/start 时应用 selector 的 `default`。

收益：连接态能展示真实流量；节点切换稳定（不崩溃），并保留未来与设置页对齐测速/延迟的演进空间。

#### Phase B（中风险）：未连接时也能展示“节点列表”（无 command.sock）
目标：至少做到“未连接也能看到节点/可选择”，并为后续真正测速打基础。

实现思路：
1. 从当前选中的 Profile 读取 config JSON：`ProfileManager.get(selectedProfileID)` + `profile.read()`。
2. 解析 JSON，提取：
   - selector/urltest 出站组（`type == selector/urltest`）
   - 组内候选节点 tags（如 `meshflux150/meshflux170`）
   - default/selected（若配置有 `default` 字段）
3. 将解析结果作为“离线节点列表”展示在节点窗口内：
   - 地区字段可先由 tag 映射（占位）或从 provider 元数据补齐（后续）
   - 延迟：若无数据则显示 `—`
4. 当用户在未连接状态选择某节点：
   - 先把选择写入 `SharedPreferences`（新 key，例如 `selectedOutboundTagForMainGroup`）
   - 当 VPN 连接成功后（监听 `vpnController.isConnected`），再调用 `selectOutbound` 应用到运行态

收益：未连接也能展示节点列表与选择；代价是需要写一个 JSON 解析器与 selection 持久化。

状态：✅ 已完成（菜单节点列表来自 Profile config JSON；选择按 profile 维度持久化；连接态通过 extension reload 应用）。

#### Phase C（高风险）：未连接时也能“真实测速”
这里有两个路线：

路线 1（推荐先做）：**“预估测速”**（不等同于 urltest）
- 直接对节点服务器地址做 TCP connect/ICMP（若可）/HTTPS HEAD，得到一个基础 RTT
- 优点：实现快，不依赖 extension
- 缺点：不等同于“通过代理链路的 urltest”，仅能当参考

路线 2（追求一致）：**在主 App 内启动一个临时 libbox 实例做 urltest**
- 需要确认 OpenMeshGo/OMLibbox 是否提供“无需 PacketTunnel 的 urltest API”
- 若目前库不支持，需要扩展 Go 层导出 API（工程量较大）

建议：先落地路线 1（保证产品体验），并在工程内留出接口以便未来替换为路线 2。

状态：
- ✅ 连接态：菜单“测速”已通过 extension IPC 调用 libbox/urltest（与设置页语义对齐）。
- ⚠️ 离线（未连接）：仍是路线 1 的“直连 TCP RTT 估算”（仅参考，且可能与 urltest 差异较大）。
- ⏳ 路线 2（未连接真实测速）：仍待评估/设计。

---

## 7. 视觉风格（与 mesh_logo 一致）

参考 App 图标 `openmesh-apple/MeshFluxMac/Assets.xcassets/AppIcon.appiconset/mesh_logo.png`：
- 主色调：天空蓝渐变背景 + 白色主体图形（鸽子）
- 风格关键词：轻盈、圆角、简洁、高对比（白/蓝）、少量强调色

菜单【设置】Tab 的 UI 建议统一为：
- 连接/商户区与其它信息块保持一致的轻卡片风格（圆角 12–14，轻边框，阴影/高斯效果尽量少）
- 强调色：沿用当前 Tab 下划线的橙色（或改为品牌蓝，后续统一）
- 字体：标题 semibold，数值用等宽（monospaced）提升可读性

### 可选素材（如果你愿意提供/我也可以从现有素材裁切）
为进一步贴近图标风格、提升质感，建议新增以下资源（可选，不影响功能）：
1. `mesh_logo_small`（小尺寸透明背景 PNG 或 PDF）：用于 Hero 区左侧装饰/占位图（不使用 AppIcon 直接引用，避免资源名/渲染差异）
2. `bg_wave_light`（淡蓝波纹背景，透明 PNG）：用于 Hero 区底纹，降低纯色渐变的“平”
3. `icon_traffic_total` / `icon_node`（一组同风格线性图标，可用 SF Symbols 先占位）

---

## 8. UI/交互建议（便于后续接真实数据）

为了便于未来接入真实数据，建议将 UI 组件做成“纯展示 + 输入数据”的结构：
- `NodeLatencyListView(nodes: [NodeLatency], onTestSpeed: () -> Void, onSelect: (id) -> Void)`
- `TrafficRateView(uplink: String, downlink: String)`
- `TrafficTotalCardView(left: String, total: String, seriesUp: [Double], seriesDown: [Double], onMoreInfo: () -> Void)`

本轮实现可在 `MenuBarWindowContent` 内创建一个 `@State` 的假数据模型（或在独立 View 内用 timer 生成），但要保证：
- 菜单窗口关闭后 timer 释放
- 不影响 VPNController 的生命周期与连接逻辑

---

## 9. 验收清单（基于当前代码）

1. 打开菜单栏弹窗，顶部 Tab 显示为：`DashBoard / Market / Settings`
2. DashBoard Tab 中：
   - Start/Stop 单按钮（两张图切换）可用
   - 可选择“流量商户”
   - 有流量曲线图（上下行）
   - 曲线图下方有“节点+速率”信息行（含「切换」按钮）
   - 点击「切换」打开节点窗口（供应商标题、全局/单行测速按钮）
   - 左下角齿轮为菜单（Update/About/Source/Start at login/Preferences）
   - Preferences 可打开旧 split-view 设置窗口

---

## 10. 可直接开工的实施清单（按优先级）

> 目标：在不推翻现有 UI 的前提下，快速完成“假数据 -> 真实数据（连接态）-> 离线可用（未连接态）”。

### 10.1 Sprint 1（P0，先把连接态跑通）

#### Task 1：接入真实流量状态（StatusCommandClient）
- 目标：替换 DashBoard 内流量假数据（上下行速率 + 累计）。
- 文件：
  - `openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`
  - `openmesh-apple/MeshFluxMac/views/DashboardView.swift`（参考其状态消费逻辑）
- 实施：
  1. 在 DashBoard 对应 ViewModel 或 View 内新增 `StatusCommandClient` 生命周期管理（connect/disconnect）。
  2. 订阅/轮询 `status`，将 `uplink/downlink/uplinkTotal/downlinkTotal` 映射到 UI 展示字段。
  3. 删除或下线假数据 timer（保留 debug 开关可选）。
- 完成标准（DoD）：
  - VPN 已连接时，速率数字会实时变化；
  - 累计值非固定假值；
  - 关闭菜单窗口后无多余定时器/订阅残留。

状态：✅ 已完成。

#### Task 2：接入真实节点信息（GroupCommandClient）
- 目标：替换“节点+速率行”和节点弹窗中的假节点列表。
- 文件：
  - `openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`
  - `openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`
  - `openmesh-apple/MeshFluxMac/views/GroupsView.swift`（参考）
  - `openmesh-apple/MeshFluxMac/core/GroupCommandClient.swift`
- 实施：
  1. 仅在 `vpnController.isConnected == true` 时连接 `GroupCommandClient`。
  2. 从 `groups` 中定位主 selector/urltest 组，提取 `selected`、`items`、延迟信息。
  3. “切换”窗口列表改为真实 `groups` 数据。
- 完成标准（DoD）：
  - 连接态下，DashBoard 显示当前真实节点名；
  - 节点弹窗列表与旧 Groups 页面数据一致（数量与 tag 可对齐）；
  - 断开 VPN 后不报错，UI 退回占位态。

状态：⚠️ 菜单路径不采用 `GroupCommandClient`（稳定性原因，见第 4.1 节）；节点列表改为离线解析（JSON）。

#### Task 3：节点测速与切换动作落地
- 目标：节点窗口内“测速/选择”动作可真实生效。
- 文件：
  - `openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`
- 实施：
  1. 全局测速按钮绑定 `urlTest(groupTag:)`。
  2. 单行测速按钮绑定单节点触发（如当前协议仅支持组测速，则在 UI 标注“刷新本组延迟”）。
  3. 选择节点后调用 `selectOutbound(groupTag:, outboundTag:)` 并刷新选中态。
- 完成标准（DoD）：
  - 点击测速后延迟数据可刷新；
  - 选择节点后 UI 选中态正确；
  - 重新打开窗口仍显示当前运行态选中节点。

状态：✅ 切换已完成（保存偏好 + extension reload 应用）；⚠️ 测速语义遗留（见第 6.2 Phase C）。

---

### 10.2 Sprint 2（P1，补齐未连接态“可看可选”）

#### Task 4：实现离线节点解析（从 Profile JSON）
- 目标：未连接 VPN 时也能显示节点列表（离线数据源）。
- 文件（建议新增）：
  - `openmesh-apple/MeshFluxMac/core/OfflineGroupResolver.swift`
  - `openmesh-apple/MeshFluxMac/core/models/OfflineGroupModels.swift`
- 依赖：
  - `ProfileManager.get(selectedProfileID)`
  - `profile.read()`
- 实施：
  1. 解析 config JSON 的 outbounds，筛选 `selector/urltest`。
  2. 提取主组 tag、候选节点 tags、默认节点（若有）。
  3. 输出统一模型供 `MenuNodePickerWindowView` 渲染。
- 完成标准（DoD）：
  - VPN 未连接时节点窗口仍可展示列表；
  - 若解析失败，UI 显示可读错误/空态，不崩溃。

状态：✅ 已完成。

#### Task 5：离线选择持久化 + 连接后回放
- 目标：未连接时选中的节点，连接成功后自动应用到运行态。
- 文件：
  - `openmesh-apple/MeshFluxMac/core/SharedPreferences.swift`（或对应偏好封装）
  - `openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`
  - `openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`
- 实施：
  1. 新增 key：`selectedOutboundTagForMainGroup`（可按 profile 维度扩展）。
  2. 未连接选择时仅写偏好，不调用 command.sock。
  3. 监听 `vpnController.isConnected` 从 false -> true 时执行一次 `selectOutbound` 回放并清理“待应用状态”。
- 完成标准（DoD）：
  - 离线选择后重启 App 仍保留；
  - 下次连接成功后自动切到该节点；
  - 回放失败有日志且不会阻塞主流程。

状态：✅ 已完成（回放实现为 extension reload 应用 selector default）。

---

### 10.3 Sprint 3（P2，未连接态测速能力）

#### Task 6：预估测速（非 urltest）最小可用实现
- 目标：未连接时提供可用的“参考延迟”。
- 文件（建议新增）：
  - `openmesh-apple/MeshFluxMac/core/NodeLatencyEstimator.swift`
- 实施：
  1. 优先 TCP connect RTT（超时如 1500ms），失败回退 `—`。
  2. 提供全局测速与单节点测速接口（async/await）。
  3. UI 文案标注“预估”避免与连接态真实 urltest 混淆。
- 完成标准（DoD）：
  - 未连接时可触发测速并看到结果；
  - 连接态仍优先使用 `GroupCommandClient.urlTest`。

状态：⚠️ 已实现为直连 TCP RTT 估算，但目前与设置页「出站组」测速不一致，下一轮需要对齐语义。

---

### 10.4 横切任务（每个 Sprint 都做）

#### Task 7：状态机统一（避免 UI 逻辑分叉失控）
- 建议引入统一数据源状态：
  - `disconnectedOfflineData`
  - `connectedLiveData`
  - `loading`
  - `error`
- 在 `MenuSettingsPrimaryTabView` 与 `MenuNodePickerWindowView` 共用一套状态定义，避免重复判断。

#### Task 8：日志与错误提示
- 所有 command client 调用失败都打统一前缀日志（例如 `[MenuDashboard]`）。
- 用户可见错误只保留必要信息（如“节点数据加载失败，请重试”），技术细节写日志。

#### Task 9：回归检查清单（每次提测前执行）
1. 连接态：速率/累计/节点列表/节点切换/测速全部可用；
2. 断开态：节点列表可见，离线选择可保存；
3. 断开 -> 连接：离线选择能自动应用；
4. 连接 -> 断开：UI 不崩溃，自动切换到离线数据源；
5. 菜单窗口反复开关 20 次，无明显内存增长或重复订阅。

---

### 10.5 建议分支与提交粒度（可选）

- 分支名：`codex/menu-dashboard-live-data`
- 提交建议（每个可独立回滚）：
  1. `feat(mac-menu): wire dashboard traffic to StatusCommandClient`
  2. `feat(mac-menu): wire node list and selection to GroupCommandClient`
  3. `feat(mac-menu): add offline group resolver and persisted selection`
  4. `feat(mac-menu): add offline latency estimator for disconnected state`

---

## 11. 连接前预检与自动兜底（方案 2：extension 内 urltest + UI 状态门禁）

> 背景：当前“真实 urltest（设置->出站组）”依赖 extension 运行态。如果默认节点不可用，VPN 启动可能失败/卡住，用户又无法依赖“先连上再测速”来诊断原因，体验很差。
>
> 目标：把“节点可用性判断 + 自动切换到可用节点”前置到 PacketTunnelProvider 启动流程里，并在 UI 上做门禁：
> - VPN 未连接/未启动：菜单不展示「切换」按钮；节点窗口若被打开，测速/切换必须提示“先连接 VPN”。
> - VPN 启动时：extension 先做 urltest/可用性预检并自动挑选可用节点作为 selector default，再启动服务。
> - 全部节点不可用：extension 把明确错误原因通知 UI 主进程（并让 VPN 启动失败），避免“黑盒卡死”。

### 11.1 UI 侧修改清单（门禁 + 提示）

#### Task U1：未连接时隐藏「切换」入口
- 修改文件：`openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift`
- 行为：
  1. 当 `vpnController.isConnected == false` 时，不显示「切换」按钮（或显示为 disabled + tooltip，但本方案优先“完全隐藏”）。
  2. 当 `vpnController.isConnected == true` 时才显示「切换」按钮，允许进入节点切换界面。
- 验收：
  - VPN 未连接时，菜单中看不到「切换」。
  - VPN 连上后，「切换」出现且可点击。

#### Task U2：节点切换窗口强制检查 VPN 状态
- 修改文件：`openmesh-apple/MeshFluxMac/views/MenuNodePickerWindowView.swift`（需要注入/读取 VPN 状态，或由 store 暴露 `requiresConnected`）
- 行为：
  1. 若当前不在连接态：点击“测速”必须弹窗/提示 `请先连接 VPN`，并且按钮应 disabled（避免误触/误解）。
  2. 若连接态：测速走真实 urltest（见 11.2），并显示“测速中…”状态（按钮不可重复点击）。
- 验收：
  - 未连接时点击测速不会发生任何网络动作，只提示“先连接 VPN”。
  - 连接态测速会进入 loading，并在结果更新后退出 loading。

#### Task U3：把“全部节点不可用”的原因展示给用户
- 修改文件：`openmesh-apple/MeshFluxMac/core/VPNController.swift` / `openmesh-apple/MeshFluxMac/core/VPNManager.swift`（视现有连接错误流而定）
- 行为：
  - extension 若判定“无可用节点”，应将原因写入 SharedPreferences（例如 `lastStartupFailureReason`），并返回错误导致连接失败；UI 在连接失败后读取并展示该原因（alert/toast）。
- 验收：
  - 所有节点不可用时，UI 能看到明确提示（例如“所有节点不可达，请切换供应商或检查网络”），而不是无限 loading。

### 11.2 extension 侧修改清单（PacketTunnelProvider 启动前 urltest）

#### Task E1：定义“预检”状态机与超时策略
- 修改文件：`openmesh-apple/vpn_extension_macx/PacketTunnelProvider.swift`
- 状态建议：
  - `preflightRunning`（正在预检）
  - `preflightSelectedOutboundTag`（预检选中的节点）
  - `preflightFailureReason`（失败原因）
- 超时建议：
  - 单节点 urltest timeout：例如 3s
  - 全量并发预检总 timeout：例如 6-10s（避免启动过程太久）

#### Task E2：启动流程中先验证默认节点可用性，不可用则并发测试全部候选
- 修改位置：`startTunnel(...)` 中 `buildConfigContent()` 前后（以“能在创建 service 之前修改 configContent”为准）
- 目标行为：
  1. 解析 config（或复用现有 JSON patch 流程）定位主 selector 组（优先 tag=proxy，其次 auto，其次第一个 selector/urltest 组）。
  2. 获取候选 outboundTags（selector.outbounds / urltest 组 all）。
  3. v1（已实现）：先对“默认将要使用的 outbound”做一次快速 TCP 可达性预检（connect RTT）：
     - 成功：直接进入启动。
     - 失败：对全部候选并发 TCP 预检，选出任意可达节点（可按 RTT 最小）。
  4. v2（待实现）：将 TCP 预检替换为“真实 urltest”（与设置页出站组一致的语义）。
  4. 若找到可用节点：把 selector.default 写成该节点（同 4.1/当前 reload 方案一致），继续启动 VPN 服务。
  5. 若全部失败：写入失败原因（SharedPreferences + 日志），并使 startTunnel 失败返回错误。

备注（实现策略）：
- 为保持稳定性与复用，建议把“urltest + 选择 + patch config”放到 Go/libbox 层实现为一个可导出的函数（由 Swift extension 调用），避免在 Swift 侧重写 sing-box 逻辑。
- Swift extension 侧只负责：调用预检、拿到 selected tag、把 selected tag patch 到 configContent。

#### Task E3：向 UI 主进程暴露预检结果（可选，但强烈推荐）
- 方式 A（最低成本）：写 SharedPreferences（App Group）：
  - `lastPreflightSelectedOutboundTag`
  - `lastPreflightFailureReason`
  - `lastPreflightAt`
- 方式 B（更实时）：providerMessage 推送进度/结果（需要定义 message action，例如 `preflight_progress`/`preflight_result`）

### 11.3 测试清单（一步步可验证）

#### 场景 T1：默认节点可用
1. 设置 selector.default 为一个可用节点。
2. 点击连接。
3. 预期：预检快速通过；VPN 正常连接；菜单「切换」按钮出现；节点窗口可测速/切换。

#### 场景 T2：默认节点不可用，但候选中有可用节点
1. 把 selector.default 指向一个不可达节点（或临时断开该节点）。
2. 点击连接。
3. 预期：extension 检测默认不可用 → 并发预检全部候选 → 自动选择一个可用节点 → 修改 selector.default → VPN 仍能连接成功。
4. 连接成功后：菜单「切换」按钮出现；设置页/节点页能看到当前实际使用节点与预检结果一致。

#### 场景 T3：全部节点不可用
1. 让全部候选节点不可达（或用一组无效地址）。
2. 点击连接。
3. 预期：startTunnel 在预检阶段失败；UI 结束 loading 并弹出明确错误原因；菜单不出现「切换」按钮。

#### 场景 T4：连接态测速门禁
1. VPN 未连接时：节点窗口测速按钮应 disabled，点击提示“请先连接 VPN”。
2. VPN 连接后：测速按钮可用，点击出现“测速中…”且不可重复点击，结果更新后恢复可点击。
