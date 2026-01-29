# VPN 改造工作计划：对齐 sing-box 逻辑与界面

**参考**：`/Users/wesley/MeshNetProtocol/openmesh-cli/sing-box/clients/apple`（SFI + SFM + SFM.System + Library + ApplicationLibrary + MacLibrary）

---

## 需求与目标（总览）

**主要目标**：将 `openmesh-apple` 下 **3 个 target 组合**在 VPN 方面的功能、界面、代码逻辑、系统配置，与 `sing-box/clients/apple` 下对应的 3 个 target 组合**接近完全对齐**。**仅限 VPN 能力**；区块链/支付等非 VPN 代码与能力全部保留。

| 我们的 target 组合 | 要对齐的 sing-box 侧 |
|-------------------|----------------------|
| **MeshFluxIos** + vpn_extension_ios | **SFI**（iOS App + Extension） |
| **MeshFluxMac** + vpn_extension_macos（应用级） | **SFM**（macOS App + Extension） |
| **MeshFlux.sys** + vpn_extension_macx（系统级） | **SFM.System**（System Extension） |

**执行顺序**：
1. **先做 Mac 应用级**（MeshFluxMac + vpn_extension_macos）→ 改造完成后进行测试。
2. **测试通过、功能可用后**，再改造 **iOS**（MeshFluxIos + vpn_extension_ios）和 **Mac 系统级**（MeshFlux.sys + vpn_extension_macx），使二者在 VPN 方面也与 sing-box 对应 target 接近完全对齐。

---

## 当前进展与状态（会随测试与后续改造更新）

| 范围 | 状态 | 说明 |
|------|------|------|
| **Mac 应用级**（MeshFluxMac + vpn_extension_macos） | ✅ 改造完成，**待测试** | 见下方「Mac 应用级已完成项」。测试通过后可进入下一阶段。 |
| **iOS**（MeshFluxIos + vpn_extension_ios） | ⏳ 待改造 | 计划在 Mac 应用级验证通过后进行。 |
| **Mac 系统级**（MeshFlux.sys + vpn_extension_macx） | ⏳ 待改造 | 计划在 Mac 应用级验证通过后进行。 |

**Mac 应用级已完成项**：
- **数据层**：VPNLibrary（Database、Profile、ProfileManager、SharedPreferences、FilePath、ExtensionProfile）已就绪；主 App 与 vpn_extension_macos 均使用。
- **Extension Profile 驱动**：vpn_extension_macos 启动时优先 `selectedProfileID` → Profile → `profile.read()`；无有效 Profile 时回退到 bundled `default_profile.json`，再回退到 legacy `buildConfigContent()`（读 App Group 的 routing_rules / singbox_config）。
- **主 App UI**：Dashboard（启停）、配置列表（新建/编辑/删除）、Settings、日志（实时 command.sock + 文件回退）、导入配置（URL/本地文件）；侧栏含「服务器」「自定义」Tab 并已注明**仅影响无配置时的回退**。
- **首次/空配置**：Profiles 为空时自动从 bundled `default_profile.json` 创建「默认配置」并选中；用户也可在空列表点击「使用默认配置」。
- **LibboxSetup**：主 App 启动时调用 `OMLibboxSetup`，使 Logs 页能通过 command.sock 连接 extension 获取实时日志。

**后续计划**：Mac 应用级测试通过后，按同一套思路改造 iOS 与 Mac 系统级（功能、界面、逻辑、配置对齐 sing-box 对应 target）。

---

## 一、现状与目标差异（简要）

| 维度 | 当前 openmesh-apple | 目标（对齐 sing-box） |
|------|---------------------|------------------------|
| 配置来源 | 共享目录文件（shared/ + App Group） + 代码拼装 | 用户创建的 **Profile**，每 Profile 对应一份完整 config 文件（存 App Group/configs/） |
| 主程序→Extension | 不传 config 内容，Extension 读 App Group 文件并 buildConfigContent() | 不传 config 内容，Extension 读 **selectedProfileID** → Profile → profile.read() 得到完整 config 字符串 |
| 存储 | routing_rules.json、singbox_config.json 等独立文件 | **Database**（settings.db：profiles 表 + preferences 表）+ **configs/** 下 JSON 文件 |
| UI | 简单 Tab（VPN 开关、服务器配置、自定义规则） | **Dashboard + Profiles + Settings + Logs**，Profile 列表/新建/编辑/导入，按选中 Profile 启停 |
| 工程结构 | MeshFluxMac / vpn_extension_macos / SharedCode 等 | 引入 **Library**（Database+Network+Shared）、**ApplicationLibrary**（Views），主 App 只做入口与菜单 |

---

## 二、阶段一：数据层与共享层（Library）

**目标**：引入与 sing-box 一致的 Profile、Database、SharedPreferences、FilePath，仅限 VPN 使用。

1. **新建 target：VPNLibrary（或复用/重命名 SharedCode 为 VPN 专用库）**
   - 职责：Database、Profile、SharedPreferences、FilePath、ExtensionProfile（与 Extension 通信的 API）。
   - 不包含 UI；可被 MeshFluxMac、MeshFluxIos、vpn_extension_macos、vpn_extension_ios、MeshFlux.sys 等引用。

2. **FilePath（VPN 用）**
   - 路径：`VPNLibrary/Shared/FilePath.swift`（或 `SharedCode/FilePath.swift` 仅 VPN 使用）。
   - 内容对齐 sing-box：`groupName` = 我们的 App Group（如 `group.com.meshnetprotocol.OpenMesh`），`sharedDirectory`、`cacheDirectory`、`workingDirectory`、`iCloudDirectory` 与 sing-box 一致。
   - 确保主 App 与 Extension、System Extension 使用同一 groupName。

3. **Database（GRDB）**
   - 路径：`VPNLibrary/Database/`。
   - 文件：`Databse.swift`（单例，settings.db 放在 `FilePath.sharedDirectory`），schema 与 sing-box 一致：
     - 表 `profiles`：id, name, order, type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated。
     - 表 `preferences`：name, data（用于 SharedPreferences）。
   - 依赖：引入 GRDB（与 sing-box 一致），或先用 SQLite + 简单封装，后续再对齐 GRDB。

4. **Profile 模型**
   - 路径：`VPNLibrary/Database/Profile.swift`、`Profile+Date.swift`、`Profile+Hashable.swift`、`Profile+RW.swift`、`Profile+Share.swift`、`Profile+Transferable.swift`、`Profile+Update.swift`。
   - 行为与 sing-box 一致：
     - `Profile.read()`：local/remote 用 `path`（需为绝对路径或基于 sharedDirectory 的路径），icloud 用 iCloud path。
     - `Profile.write(content)`：写回对应路径。
   - 新建 Profile 时，config 文件路径：`FilePath.sharedDirectory.appendingPathComponent("configs").appendingPathComponent("config_\(id).json")`，path 存相对或绝对（与 Profile+RW 实现一致）。

5. **ProfileManager**
   - 路径：`VPNLibrary/Database/ProfileManager.swift`。
   - API：create, get(id), get(by name), update, delete, list, listRemote, listAutoUpdateEnabled 等，与 sing-box 一致。

6. **SharedPreferences（DB 持久化）**
   - 路径：`VPNLibrary/Database/SharedPreferences.swift`、`ShadredPreferences+Database.swift`（或正确拼写 SharedPreferences+Database）。
   - 至少包含：`selectedProfileID`、`alwaysOn`、`includeAllNetworks`、`maxLogLines` 等 VPN 相关项；存储到 `preferences` 表（与 sing-box 一致）。

7. **ExtensionProfile（与 NEVPNManager 对接）**
   - 路径：`VPNLibrary/Network/ExtensionProfile.swift`。
   - 行为：load/install manager，start/stop VPN；start 时只调用 `startVPNTunnel()`，**不**向 extension 传 config 内容；启动前可 fetchProfile（预拉当前选中 profile，如 iCloud）。
   - 若支持 System Extension：macOS 下 useSystemExtension 时 options 传 username 等（与 sing-box 一致）。

8. **移除或隔离旧“共享文件”逻辑**
   - `RoutingRulesStore`、`SingboxConfigStore` 等：保留类型与 API，但改为“仅用于迁移或默认模板”；新逻辑以 Profile + config 文件为准。
   - 或：在 Phase 1 仅增加 Library 层，暂不删旧代码，待 Extension 改为读 Profile 后再废弃。

**交付物**：VPNLibrary target，包含 FilePath、Database、Profile、ProfileManager、SharedPreferences、ExtensionProfile；主 App 与 Extension 能编译并链接 VPNLibrary。

---

## 三、阶段二：Extension 改为 Profile 驱动

**目标**：vpn_extension_macos / vpn_extension_ios（及可选 System Extension）启动时从 SharedPreferences + Profile 读取 config，不再从 routing_rules.json + singbox_config 拼装。

1. **vpn_extension_macos**
   - 在 `startTunnel` 中：
     - 使用 FilePath.sharedDirectory（与 VPNLibrary 一致）做 basePath/workingPath/tempPath。
     - 读 `SharedPreferences.selectedProfileID.get()`，再 `ProfileManager.get(profileID)`，再 `configContent = try profile.read()`。
     - 调用 `LibboxNewService(configContent, platform, &err)` 启动，**不再**调用 `buildConfigContent()`。
   - 删除或保留 `buildConfigContent()`、`DynamicRoutingRules` 的“从文件拼装”逻辑为兼容/迁移用；正常路径仅用 profile.read() 的完整 config。

2. **vpn_extension_ios**
   - 同上，改为 selectedProfileID → Profile → profile.read() → LibboxNewService(configContent)。

3. **OpenMesh.Sys-ext（System Extension）**
   - 若当前通过 providerConfiguration 注入 config 内容，改为：Extension 内使用同一 FilePath/SharedPreferences/ProfileManager，读 selectedProfileID 与 profile.read()；若 System Extension 无法访问 App Group 路径，则保留“注入 config 字符串”作为 fallback，但主程序侧写入的 source 仍为“当前选中的 Profile 的 config 文件内容”（与 sing-box SFM.System 思路一致）。

4. **Extension 依赖**
   - vpn_extension_macos / vpn_extension_ios 依赖 VPNLibrary（仅链接，不包含 UI）。

**交付物**：Extension 仅靠 Profile + selectedProfileID 运行，不再依赖 shared 目录下的 routing_rules.json/singbox_config 拼装。

---

## 四、阶段三：主 App UI 对齐 sing-box（Dashboard / Profiles / Settings / Logs）

**目标**：MeshFluxMac 的 VPN 部分使用与 sing-box 相同的导航与页面结构；非 VPN 部分（区块链、支付等）保留在独立 Tab/Scene 中。

1. **新建 ApplicationLibrary target（仅 VPN 相关 View）**
   - 路径：`ApplicationLibrary/Views/`。
   - 包含：NavigationPage、Dashboard（StartStopButton、Overview、InstallProfileButton 等）、Profile（ProfileView、NewProfileView、EditProfileView、ImportProfileView）、Setting（SettingView、ProfileOverrideView、OnDemandRulesView 等）、Log（LogView）。
   - 依赖：VPNLibrary、SwiftUI；不依赖 App 业务（区块链等）。

2. **MacLibrary（或集成进 MeshFluxMac）**
   - 主窗口结构对齐 sing-box：NavigationSplitView + SidebarView + detail（NavigationStack + selection.contentView）。
   - 侧栏项：Dashboard、Profiles、Settings、Logs（与 NavigationPage 一致）；可选增加“钱包/支付”等我们自己的入口。
   - MenuBarExtra：保留现有菜单栏入口，内容可改为“Dashboard + 启停 + 其它快捷入口”。

3. **MeshFluxMac 入口与依赖**
   - App 入口：`@main` + `NSApplicationDelegateAdaptor` 的 ApplicationDelegate。
   - ApplicationDelegate：在 `applicationDidFinishLaunching` 中做 LibboxSetup（basePath/workingPath/tempPath 用 FilePath）、ProfileUpdateTask.configure()、若需开机自启则 ExtensionProfile.load() + start()。
   - 主界面：使用 ApplicationLibrary 的 MainView（或等价），侧栏 + Dashboard/Profiles/Settings/Logs；在同一个 Window 或 Tab 中嵌入“服务器/支付”等我们自己的 View（或单独 Tab）。

4. **Profile 创建/编辑/导入**
   - NewProfileView：类型选 Local/Remote/iCloud；Local 时选择“新建空 config”或“从文件导入”，config 写入 `FilePath.sharedDirectory/configs/config_\(id).json`，path 存入 Profile。
   - EditProfileView：打开当前 profile 的 config 文件内容，可编辑后写回。
   - ImportProfileView：从 URL 或文件导入，写入 configs 并创建 Profile。
   - 与 sing-box 的 NewProfileView/EditProfileView/ImportProfileView 行为一致。

5. **Dashboard**
   - 显示当前选中 Profile 名称、连接状态；Start/Stop 调用 ExtensionProfile.start()/stop()。
   - 若有 System Extension，可保留“安装系统扩展”按钮（等价 InstallSystemExtensionButton）。

6. **Settings**
   - 至少包含：Always On、Include All Networks、Log 相关、Profile Override（路由相关）等，数据来自 SharedPreferences。

7. **Logs**
   - 通过 CommandClient 或等价方式连接 Extension 的 log 流并展示（与 sing-box LogView 一致）。

**交付物**：MeshFluxMac 具备与 sing-box SFM 一致的 VPN 导航与 Profile 管理；非 VPN 功能仍在独立区域保留。

---

## 五、阶段四：工程配置与结构对齐

**目标**：Xcode 工程结构、target 依赖、App Group、Entitlements、Extension 的 bundle id 与 sing-box 可对照，便于后续同步升级。

1. **Target 依赖关系**
   - MeshFluxMac：依赖 VPNLibrary、ApplicationLibrary、MacLibrary（若独立）。
   - vpn_extension_macos / vpn_extension_ios：仅依赖 VPNLibrary（及 OpenMeshGo）。
   - MeshFlux.sys / OpenMesh.Sys-ext：依赖 VPNLibrary；若 System Extension 不能直接访问 App Group，则主 App 在启动 VPN 前将“当前选中 Profile 的 config 内容”写入 providerConfiguration 作为 fallback（与现有逻辑兼容）。

2. **App Group**
   - 统一使用同一 Group ID（如 `group.com.meshnetprotocol.OpenMesh`），主 App、Extension、System Extension 的 entitlements 均配置该 Group。
   - FilePath.groupName 与该 ID 一致。

3. **Bundle ID / 产品名**
   - 保持现有：如 com.meshnetprotocol.OpenMesh.mac、com.meshnetprotocol.OpenMesh.mac.vpn-extension 等；仅确保与 sing-box 的“命名风格”可对照（packageName.extension / packageName.system）。

4. **Extension 安装与首次启动**
   - 与 sing-box 一致：首次启动时若无 NETunnelProviderManager，则调用 ExtensionProfile.install()；再 load 后 start。

5. **资源与本地化**
   - 将 VPN 相关字符串抽到 Localizable.xcstrings（或等价），便于与 sing-box 对照和后续多语言。

**交付物**：工程可编译、运行，VPN 流程与 sing-box 一致；文档中注明 target 与 sing-box 的对应关系（SFM ↔ MeshFluxMac，Extension ↔ vpn_extension_macos 等）。

---

## 六、阶段五：迁移与兼容

**目标**：已有用户从“共享文件”模式平滑过渡到 Profile 模式；旧能力可读不可写或提供一键迁移。

1. **首次启动迁移**
   - 若 App Group 内已有 `routing_rules.json` 或 `singbox_config.json`，且 profiles 表为空：自动创建一个默认 Profile（如“默认配置”），将现有 config 内容写入 `configs/config_default.json`，插入 Profile 并设为 selectedProfileID。
   - **shared 两文件与 Profile 的关系**：见 `docs/SHARED_TO_PROFILE.md`。合并逻辑使用 `SharedCode/ProfileFromShared.swift` 中的 `buildMergedConfigFromShared(baseConfigJSON:routingRulesJSON:routingMode:)`，将 routing_rules.json（命中 URL 规则）+ singbox_base_config.json（连接服务器配置）合并为一份完整 sing-box config 字符串，再写入 config 文件并创建 Profile。
   - 之后 Extension 只走 Profile 路径。

2. **保留“服务器配置”入口（可选）**
   - 当前“服务器配置”页可保留为“快速编辑当前选中 Profile 的 outbound”的简化入口，或改为打开 EditProfileView 的快捷方式；底层仍以 Profile 的 config 文件为准。

3. **清理**
   - 确认不再需要从 shared/ 目录同步 routing_rules 到 App Group 作为唯一数据源后，移除或标记废弃 RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded 的调用；SingboxConfigStore 同理，仅作默认模板或迁移用。

**交付物**：升级后的 App 首次启动完成迁移；旧配置文件不再被 Extension 直接读取，仅通过 Profile 使用。

---

## 七、保留不变的部分（非 VPN）

- **MeshFluxIos**：现有 auth、main、钱包、支付等逻辑与 UI 不变；仅 VPN 相关部分（若有）改为使用 VPNLibrary + ExtensionProfile + Profile。
- **MeshFluxMac**：服务器配置 Tab、自定义规则 Tab、支付/区块链相关 Tab 或 Scene 保留；仅结构调整为“VPN 用 Dashboard/Profiles/Settings/Logs，其它用独立 Tab/区域”。
- **OpenMesh.Sys / MeshFlux.sys**：系统扩展的安装与卸载流程保留；仅 Extension 内部改为读 Profile。
- **go-cli-lib、OpenMeshGo**：无变更；仍由 Extension 调用 LibboxNewService(configContent) 等。

---

## 八、建议执行顺序与优先级

| 顺序 | 阶段 | 说明 |
|------|------|------|
| 1 | 阶段一：数据层与共享层 | 先有 Profile、DB、SharedPreferences、ExtensionProfile，再改 Extension |
| 2 | 阶段二：Extension 改为 Profile 驱动 | 去掉 buildConfigContent 主路径，改为 profile.read() |
| 3 | 阶段四（部分）：Target 与 App Group | 确保 VPNLibrary、Extension 依赖与 App Group 正确，便于联调 |
| 4 | 阶段三：主 App UI | Dashboard/Profiles/Settings/Logs 与 sing-box 对齐 |
| 5 | 阶段四（剩余）：工程与配置 | 文档、本地化、bundle id 对照 |
| 6 | 阶段五：迁移与兼容 | 默认 Profile 迁移、旧入口清理 |

---

## 九、参考文件清单（sing-box/clients/apple）

- **Library**：`Library/Database/`（Databse, Profile*, ProfileManager, SharedPreferences*），`Library/Network/`（ExtensionProfile, ExtensionProvider, FilePath 在 Shared/），`Library/Shared/FilePath.swift`。
- **ApplicationLibrary**：`ApplicationLibrary/Views/`（NavigationPage, Dashboard/, Profile/, Setting/, Log/）。
- **MacLibrary**：`MacLibrary/ApplicationDelegate.swift`，`MacLibrary/MainView.swift`，`MacLibrary/MenuView.swift`，`MacLibrary/SidebarView.swift`。
- **SFI**（iOS）：`SFI/`（Application、MainView 等）+ Extension。
- **SFM**（macOS 应用级）：`SFM/Application.swift`（入口），`MacLibrary/`，Extension。
- **SFM.System**（macOS 系统级）：`SFM.System/`，System Extension。
- **Extension**：`Extension/PacketTunnelProvider.swift`（继承 ExtensionProvider，无额外逻辑）。

---

以上为完整工作计划；**实际进展与状态以本文档开头的「当前进展与状态」为准**，实施时可按阶段交付并做小幅调整（如先不做 iCloud Profile，仅 Local/Remote）。
