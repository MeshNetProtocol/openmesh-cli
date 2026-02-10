# MeshFluxMac 市场能力同步到 MeshFluxIos（方案与实施计划）

## 1. 整体需求

### 1.0 强制约束（新增，最高优先级）
- **iOS 不再保留“默认官方供应商自动注入”行为**。
- **所有供应商地位完全一致**：不允许“内建特权供应商”绕过市场安装/更新/卸载链路。
- **所有供应商配置本地隔离**：每个供应商独立目录、独立配置文件、独立规则文件；互不干涉、互不覆盖。
- 此约束优先级高于历史兼容逻辑，若冲突以本约束为准。

### 1.1 目标
- 把 `MeshFluxMac` 已完成的“供应商市场 + 安装/卸载向导 + 离线导入增强”能力同步到 `MeshFluxIos`。
- 同步的是功能和目的，不是照搬 macOS 窗口形态和 UI 细节。
- iOS 侧要保持“轻入口 + 可观测安装流程 + 可恢复失败处理”的体验。

### 1.2 iOS 信息架构调整（必须项）
- 当前 iOS 第二个 tab 文案是“流量市场”，但页面内容是钱包信息（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxIos/views/main/MainTabView.swift:16` + `/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxIos/views/main/MeTabView.swift:38`）。
- 需要改为：
1. 把当前“流量市场”tab 改名为“钱包”（继续承载现有 `MeTabView` 内容）。
2. 新增一个 `Market` tab，用于承载从 macOS 同步过来的供应商市场能力。

### 1.3 需要在 iOS 达到的功能等价（核心）
- `Market` 入口页：推荐供应商 + 两个入口按钮（“供应商市场”“导入安装”），对应 macOS `TrafficMarketView` 的定位（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/views/TrafficMarketView.swift:96`）。
- 供应商市场管理页：搜索、地区过滤、价格/更新时间排序、刷新、Marketplace/Installed 双视图（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/views/ProviderMarketManagerView.swift:49`）。
- 安装向导：步骤状态机、右下角“正在执行/当前步骤 message”提示、重试能力（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/views/ProviderInstallWizard.swift:117`）。
- 卸载向导与执行器：连接态安全校验 + 删除 Profile + 清理 SharedPreferences 映射 + 清理 App Group providers/staging/backup（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/core/ProviderUninstaller.swift:33`）。
- rule-set 下载策略：并发 2、单个超时 20s（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/core/MarketService.swift:490`）。
- URL 导入增强：遮罩禁用、3 次重试、诊断日志、SSL 失败时 WebView 回退（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/views/OfflineImportView.swift:116` + `/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/core/WebViewTextFetcher.swift:10`）。

### 1.4 约束与边界
- iOS/macOS 运行环境不同：
  - `NSWindow/NSPanel/NSOpenPanel` 不能直接迁移，需改为 iOS 的 `Navigation` + `sheet/fullScreenCover` + `fileImporter/UIDocumentPicker`。
- 业务逻辑优先下沉共享层，iOS 侧主要做 UI 与流程编排。
- 当前 iOS 尚无 `MarketService/ProviderUninstaller/OfflineImport` 等实现，需要新增。

### 1.5 当前 iOS 与目标行为差异（必须消除）
- 当前 iOS 在 profile 为空时会自动安装默认 profile（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxIos/views/main/HomeTabView.swift:428`）。
- 目标行为是不再自动安装默认供应商；当没有可用 profile 时，UI 应引导用户去 `Market` 执行安装或导入。
- 当前 mac 代码仍可见 `official-local` 兼容痕迹（例如 `/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/views/MenuSettingsPrimaryTabView.swift:330`），iOS 同步时不应引入/扩散这类特判。

## 2. 改造方案

### 2.1 架构分层方案（先业务后界面）

#### A. 共享业务层（优先建设）
- 目标：把可跨平台复用的能力下沉，避免 iOS/macOS 各自维护一套。
- 建议新增模块（建议放在 `openmesh-apple/SharedCode` 下）：
1. `MarketTypes`：`TrafficProvider`、`ProviderPackage`、响应模型。
2. `MarketServiceCore`：市场清单/推荐拉取、ETag 缓存、安装/导入安装、并发 rule-set 下载。
3. `ProviderUninstallerCore`：卸载安全校验与清理逻辑。
4. `ProviderEventBus`：统一通知名（替代仅在 mac target 内部声明的通知常量）。

- 共享层可直接复用现有基础设施：
  - `SharedPreferences` 已有 provider 相关 key（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/VPNLibrary/Database/SharedPreferences.swift:78`）。
  - `FilePath` 已有 providers/rule-set 目录与文件路径（`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/VPNLibrary/Shared/FilePath.swift:58`）。

#### B. iOS 适配层（界面与交互）
- 新增 `Market` tab 的页面族：
1. `MarketTabView`（推荐 + 两按钮入口）
2. `ProviderMarketView`（Marketplace/Installed 双视图）
3. `ProviderInstallWizardView`
4. `ProviderUninstallWizardView`
5. `OfflineImportViewIOS`

- 映射关系：
  - macOS 窗口管理器（`ProviderMarketWindowManager` / `ProviderInstallWindowManager` / `ProviderUninstallWindowManager`）改为 iOS 的 `sheet`/`fullScreenCover`。
  - `NSOpenPanel` 改为 iOS `fileImporter` 或 `UIDocumentPickerViewController`。
  - `WKWebView` 回退逻辑保留，但生命周期改成 iOS 版本实现。

### 2.2 iOS Tab 结构重构方案
- 当前：
  - Dashboard / 流量市场(实际钱包) / 设置
- 目标：
  - Dashboard / 钱包 / Market / 设置

- 对应改造：
1. `MainTabView` 中第二个 tab 文案从“流量市场”改为“钱包”。
2. 新增第三个 tab：`Market`（英文与 mac 顶部 tab 保持语义一致）。
3. `MeTabView` 导航标题从“流量市场”改为“钱包”。

### 2.3 供应商平权与本地文件隔离（iOS 可执行说明）

#### A. 去掉默认供应商自动注入
1. 移除 `HomeTabView.loadProfiles()` 中 `list.isEmpty` 时调用 `DefaultProfileHelper.ensureDefaultProfileIfNeeded()` 的逻辑。
2. `list.isEmpty` 时不再写入任何默认 profile，只显示“未安装供应商”的明确状态和跳转 `Market` 的入口。
3. `selectedProfileID` 在无 profile 时保持 `-1`，不要隐式修正成“默认官方供应商”。

#### B. 供应商平权（禁用 special-case）
1. 禁止在 iOS 逻辑中出现 `official-local` / `官方供应商` 特判分支。
2. Install/Update/Reinstall/Uninstall 全部走同一套向导和服务层，不因供应商来源差异改变路径。
3. Dashboard/Home 只按“当前已选 profile -> provider 映射”处理，不按供应商 ID 写硬编码优先级。

#### C. 本地配置文件隔离（与 mac 目标一致）
1. 每个供应商独立目录：`MeshFlux/providers/<provider_id>/`。
2. 目录内独立文件：`config.json`、`routing_rules.json`、`rule-set/*.srs`。
3. 安装过程只写当前 provider 目录；更新时仅替换当前 provider 目录（使用 staging + backup 原子切换策略）。
4. 卸载只清理目标 provider 目录与其 staging/backup 残留，不触碰其他 provider 目录。
5. SharedPreferences 映射清理粒度按 provider/profile 精确删除，不做全量覆盖。

### 2.4 市场功能迁移策略（不照搬 UI）

#### A. Market 入口页（轻量）
- 只做推荐列表与引导动作，不承载复杂管理。
- 推荐项支持 Install/Update/Reinstall 快捷动作。
- 入口按钮：
1. 打开“供应商市场”
2. 打开“已安装”
3. 打开“导入安装”

#### B. 供应商市场页（重管理，在线供应商）
- 顶部搜索、地区过滤、排序、刷新。
- 仅展示“可安装供应商（Marketplace）”。
- 行为：Install / Update / Reinstall（进入安装向导）。

#### C. 已安装页（重管理，本地资产）
- 仅展示本地已安装 profile/provider 资产。
- 行为：Reinstall / Update / Uninstall（卸载进入卸载向导）。
- 与“供应商市场页”完全分离，不做同屏混排。

#### D. 安装向导
- 必须保留“步骤状态 + 当前步骤 message”可视反馈，避免误判卡死。
- 服务层实现并发下载 rule-set（并发 2，单个 20s timeout）。
- 安装完成后刷新 Market 数据，并向主流程发送 profile 更新通知。

#### E. 卸载向导
- 先校验 VPN 是否正在使用该 provider 对应 profile；若在用则阻止卸载并提示先断开。
- 成功卸载后执行四类清理：
1. ProfileManager 记录
2. `installed_provider_*`、`selected_outbound_tag_by_profile`
3. `MeshFlux/providers/<provider_id>`
4. `.staging/.backup` 残留

#### F. URL 导入增强
- 按钮触发后显示遮罩，禁用所有重复操作。
- URL 拉取策略：
1. 仅允许 https
2. ephemeral URLSession
3. 最多 3 次重试（带小延迟）
4. 记录诊断日志（raw/normalized/request/failingURL）
5. SSL/握手失败触发 WebView 回退并提取 `document.body.innerText`

### 2.5 风险与决策
- 风险 1：iOS 网络环境对 GitHub Pages TLS 链路不稳定（-1200 / RST）。
  - 决策：短期保留重试 + WebView 回退；中期把 seeds/market bootstrap URL 迁移到可控域名（workers.dev 或对象存储域名）。
- 风险 2：业务逻辑分叉（mac 与 iOS 各自修改导致漂移）。
  - 决策：安装/卸载/缓存逻辑统一下沉共享层，平台只保留 UI 与平台 API 适配。

### 2.6 数据迁移与兼容策略（避免脏状态）
- 对已有安装用户，新增一次迁移检查：
1. 若存在“默认 profile 但无 provider 映射”状态，不自动补映射为官方供应商；保持未绑定并在 UI 提示重新从 Market 安装。
2. 若检测到旧版特判字段或目录命名，迁移到标准 `providers/<provider_id>/...` 结构。
3. 迁移过程失败不得影响其他已安装供应商目录。

## 3. 实施步骤

### 3.1 迭代原则（小步快跑）
1. **一次只改一个完整模块**（模块内可含 UI + 调用，但不跨多个业务域）。
2. **每个模块必须可独立演示与验收**，通过后再进入下一模块。
3. **每个模块都有固定退出条件（DoD）**：编译通过 + 冒烟测试通过 + 不回退已完成模块。
4. 服务端能力默认复用 mac 已验证接口，不在 iOS 迭代中改服务器逻辑。

### 3.2 模块拆分（按建议执行顺序）

#### 模块 M0：基线与开关准备
- 范围：仅做代码扫描、开关位、日志埋点，不改业务行为。
- DoD：
1. 能在日志中区分“默认注入路径”与“市场安装路径”。
2. 不引入任何行为变化。

#### 模块 M1：Tab 信息架构重构（仅导航层）
- 范围：`Dashboard / 钱包 / Market / 设置`，`Market` 先占位。
- DoD：
1. iOS 可运行，Tab 切换正常。
2. 钱包原有功能不回退。
3. `Market` 占位页可进入。

#### 模块 M2：去默认供应商自动注入（平权基线）
- 范围：只移除 `HomeTabView` 的默认 profile 自动安装逻辑；无 profile 时引导去 Market。
- DoD：
1. 全新安装/清空数据后，不会自动创建默认官方供应商。
2. Dashboard 在无 profile 状态可解释、可引导。
3. 不出现 `official-local` 特权兜底。

#### 模块 M3：共享 Market 服务核心（无 UI）
- 范围：迁移可共享 `MarketServiceCore`/模型/通知常量，先接入 iOS 但不接完整市场页。
- DoD：
1. iOS 侧能拉取 recommended 与 manifest（含缓存回退）。
2. 单元测试覆盖：解析、缓存、错误分支。
3. 不改现有界面路径。

#### 模块 M4：Market 入口页（推荐 + 两按钮）
- 范围：实现 `MarketTabView`，只做推荐列表与入口，不做管理页。
- DoD：
1. 推荐列表可加载、刷新、错误提示。
2. “供应商市场”“导入安装”入口可打开目标页面（可先占位）。

#### 模块 M5：供应商市场页 + 安装向导闭环（Marketplace -> Install）
- 范围：实现“供应商市场页（仅在线供应商）”并打通安装向导；不包含卸载与导入。
- DoD：
1. Install/Update/Reinstall 至少一条路径可用。
2. 步骤状态机与 message 可观测。
3. rule-set 并发下载策略生效（并发 2，20s timeout）。
4. 安装后 profile/provider 映射正确写入，且仅影响当前 provider 目录。

#### 模块 M6：已安装页（Installed）与本地管理
- 范围：实现“已安装页（仅本地资产）”，不与在线市场同屏；接入 M5 已有安装能力。
- DoD：
1. 仅展示已安装 profile/provider，列表状态正确。
2. Reinstall/Update 入口可用，Update 状态与本地 hash 对比正确。
3. 与在线供应商页信息完全分离。

#### 模块 M7：卸载向导闭环
- 范围：`ProviderUninstallWizardView` + `ProviderUninstallerCore` 接入 iOS。
- DoD：
1. 在用 profile 时卸载被阻止并提示。
2. 非在用可卸载，且只清理目标 provider 的 profile/映射/目录。
3. 卸载后其他供应商不受影响。

#### 模块 M8：离线导入与 URL 诊断增强
- 范围：导入文本/文件/URL、遮罩防重入、3 次重试、WebView 回退。
- DoD：
1. URL 拉取过程有遮罩与状态提示。
2. SSL/握手失败时触发回退路径并给出可诊断信息。
3. 导入安装复用安装向导，不新增第二套安装逻辑。

#### 模块 M9：全链路联调与回归
- 范围：仅联调与修复，不加新能力。
- DoD：
1. 全路径通过：推荐安装、市场安装、更新、重装、卸载、离线导入。
2. 平权与隔离约束全部满足。
3. 输出验收记录与遗留问题清单。

### 3.3 每模块固定测试清单（执行模板）
1. 编译测试：iOS target 编译通过。
2. 冒烟测试：仅覆盖本模块新增路径 + 关键回归路径（钱包、Dashboard、设置）。
3. 隔离测试：确认未触发其他模块行为变化。
4. 数据测试：provider 映射与目录写入/删除是否只影响目标 provider。

### 3.4 迭代节奏建议
1. 一个模块对应一个 PR（或一个提交序列）。
2. 每个模块完成后先验收再开始下一个模块。
3. 优先顺序固定为：`M1 -> M2 -> M3 -> M4 -> M5 -> M6 -> M7 -> M8 -> M9`。

## 4. 验收标准（用于实施完成判定）
- 结构：iOS tab 变为 `Dashboard / 钱包 / Market / 设置`。
- 基线：iOS 在“无 profile”时不再自动创建默认官方供应商。
- 平权：不存在任何供应商 ID 特权分支（包括 `official-local` 特判）。
- 隔离：任一供应商安装/更新/卸载不会改动其他供应商目录或映射。
- 信息架构：在线供应商与本地已安装资产分离到不同页面，不在同一页面混排。
- 能力：`Market` 具备推荐入口、市场管理、安装向导、卸载向导、导入安装。
- 安全：连接态占用 profile 时卸载被阻止。
- 性能：rule-set 下载并发执行，体感等待明显低于串行。
- 稳定：URL 导入失败不再“无反馈”，具备可见进度、重试、诊断信息与回退路径。

## 5. 备注
- 本计划强调“能力等价”而非“界面像素级一致”。
- 网络侧建议后续尽快将市场/seed/bootstrap 地址迁移到可控域名，减少 TLS 链路差异带来的不确定性。
