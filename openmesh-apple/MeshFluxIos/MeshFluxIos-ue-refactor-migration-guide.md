# MeshFluxIos 迁移工作计划：同步 `ue-refactor` 的 Mac 端设计与引导方案

## 1. 文档目的

本文档用于把 `ue-refactor` 分支中已经在 `MeshFluxMac` 落地的设计语言、首次使用引导和核心管理界面结构，系统迁移到：

- `/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxIos`

这份文档不再只是描述方向，而是作为接下来 iOS 改造的执行清单。目标不是逐像素复刻 macOS，而是把已经验证有效的产品逻辑迁移到 iOS：

- 统一视觉语言
- 统一首次安装和首次连接路径
- 统一 provider / market / offline import / 节点 / 流量这些核心界面的信息层级
- 统一“先让用户快速可用，再暴露技术细节”的产品节奏


## 2. Mac 端已验证的改动范围

本计划基于 `main...ue-refactor` 在 `openmesh-apple/MeshFluxMac` 下的真实差异整理，而不是回忆性描述。

涉及的 Mac 文件：

- `OpenMeshMacApp.swift`
- `core/BootstrapFetchWindowManager.swift`
- `core/ProviderInstallWindowManager.swift`
- `views/MenuNodePickerWindowView.swift`
- `views/MenuSettingsPrimaryTabView.swift`
- `views/OfflineImportView.swift`
- `views/ProviderInstallWizard.swift`
- `views/ProviderMarketManagerView.swift`
- `views/ProviderUninstallWizard.swift`
- `views/TrafficMarketView.swift`

这些改动可以归并为 3 个核心方向：

1. 统一视觉体系
2. 重构首次使用和安装引导路径
3. 重构 provider / node / traffic 等关键页面的信息层级


## 3. 迁移总原则

### 3.1 视觉原则

- 干净、克制、专业、商用品质
- 浅蓝背景为主，不做高饱和营销风格
- 使用轻玻璃感卡片，但不过度发光
- 强调秩序感和留白，不堆说明文字
- 重要信息优先，技术信息后置

### 3.2 交互原则

- 每个页面只保留一个明确主操作
- 每个页面允许一到两个次操作
- 危险操作必须降级，不得抢主操作
- 不再使用多主按钮并列的形式
- badge 和 tag 只能辅助信息层级，不能喧宾夺主

### 3.3 产品原则

- 先让用户拿到可用配置，再让用户进入技术管理页
- 无配置时优先给出下一步动作，不强调解释
- 安装完成后尽量直接进入“可连接”状态
- 在线安装、离线导入、市场浏览要属于同一条产品路径


## 4. 主要问题与迁移目标

### 4.1 当前需要解决的问题

- 新用户第一次进入应用时，不知道第一步从哪里开始
- 没有 provider 时，首页容易变成空状态或说明堆叠
- market / install / offline import 三者关系不清晰
- 安装完成后，未必能尽快进入可连接状态
- 节点、测速、流量等技术页过早暴露，增加认知成本

### 4.2 本轮迁移的目标结果

- 首次启动时，首页明确告诉用户下一步做什么
- 获取配置之后，安装流程尽量短且反馈清晰
- 安装成功后，保留“自动切换到该配置”能力，并尽量默认开启
- 离线导入成为正式入口，而不是工具角落
- 已连接后，再突出节点、测速、流量图等管理能力


## 5. 工作计划总览

本次 iOS 迁移按“先用户路径，后工具页，最后设置页”的顺序推进，不做全量并行重构。

### 阶段一：打通首次可用路径

目标：

- 新用户第一次进入应用时，知道下一步做什么
- 下载 / 导入 / 安装后，尽快进入可连接状态

涉及页面：

- `views/main/HomeTabView.swift`
- `views/main/MarketTabView.swift`
- `views/main/OfflineImportViewIOS.swift`
- `views/main/ProviderMarketplaceView.swift`
- `views/main/InstalledProvidersView.swift`

### 阶段二：重构已连接后的工具页

目标：

- 节点切换、测速、流量图等页面在已连接场景下更专业、更收敛

涉及页面：

- `views/main/OutboundGroupSectionView.swift`
- `views/main/StatusCardsView.swift`
- `views/main/ConnectionListView.swift`

### 阶段三：统一账户与设置页

目标：

- 把视觉语言和按钮体系扩展到账户、设置、个人页

涉及页面：

- `views/SettingsTabView.swift`
- `views/SettingsView.swift`
- `views/main/MeTabView.swift`


## 6. 按功能与逻辑拆分的工作清单

下面的清单才是实际执行顺序。先做依赖强、对用户路径影响最大的部分。

### A. 视觉基线与通用组件

目的：

- 在改具体页面前，先建立统一视觉和交互基线，避免后续重复返工

工作项：

- [ ] 统一 iOS 端 header 结构
- [ ] 统一卡片样式为轻玻璃卡
- [ ] 统一主按钮 / 次按钮 / 危险按钮样式
- [ ] 统一 badge / tag 的语义和视觉权重
- [ ] 统一页面背景、分组间距、卡片内边距

建议抽象的组件：

- [ ] `MFHeaderSection`
- [ ] `MFGlassCard`
- [ ] `MFPrimaryButton`
- [ ] `MFSecondaryButton`
- [ ] `MFDangerButton`
- [ ] `MFStatusBadge`
- [ ] `MFTagChip`
- [ ] `MFStepList`
- [ ] `MFMetricCard`

完成标准：

- 后续页面改造不再各自定义按钮、卡片、header 风格
- 页面主次层级能仅靠结构识别，而不是靠额外说明

### B. 首页与首次启动引导

目的：

- 把首页从“状态展示页”改成“首次可用引导页 + 已连接状态页”

对应页面：

- `views/main/HomeTabView.swift`
- `views/main/StatusCardsView.swift`
- `views/main/ConnectionListView.swift`

工作项：

- [ ] 重新整理首页在“无配置 / 已配置未连接 / 已连接”三种状态下的层级
- [ ] 无配置时，首页主区聚焦“开始配置 / 导入配置 / 打开市场”
- [ ] 已配置未连接时，强化当前 provider、连接入口和下一步动作
- [ ] 已连接时，再提升状态卡、流量摘要、节点入口的权重
- [ ] 减少无意义说明文案，改为结构化引导
- [ ] 校正首页上的主按钮数量，确保只有一个主操作

完成标准：

- 用户第一次打开应用时，不需要理解技术名词也知道下一步该做什么
- 首页不会在无配置时变成空白状态或灰字堆叠

### C. Market 推荐与配置获取入口

目的：

- 让 Market 不像商城首页，而像“获取配置的精选入口”

对应页面：

- `views/main/MarketTabView.swift`

工作项：

- [ ] 重构 Market 页 header，明确页面定位
- [ ] 将推荐 provider 呈现为精选入口面板，而不是信息墙
- [ ] 统一 section header 结构：左侧标题，右侧主次操作
- [ ] provider card 改为单列、紧凑、统一的安装 CTA
- [ ] 弱化 tag 的视觉权重，避免和主标题竞争

完成标准：

- 用户能在 Market 页面快速理解“这里是拿配置的入口”
- 卡片信息一眼能看出：是什么、能否安装、下一步做什么

### D. Provider Marketplace 与 Installed 管理

目的：

- 把“浏览资源”和“管理已安装项”拆清楚

对应页面：

- `views/main/ProviderMarketplaceView.swift`
- `views/main/InstalledProvidersView.swift`

工作项：

- [ ] 明确 `Marketplace` 和 `Installed` 的职责边界
- [ ] `Marketplace` 页按资源浏览逻辑设计
- [ ] `Installed` 页按管理列表逻辑设计
- [ ] 清理 `Installed` 页中的按钮墙问题
- [ ] 统一更新、重装、卸载按钮语言和摆放层级
- [ ] 危险操作弱化，但保留明确可达性

完成标准：

- 用户不会在同一页面同时处理“浏览”和“管理”两种心智任务
- 已安装列表中的操作层级一眼可分

### E. 离线导入与安装入口统一

目的：

- 让离线导入成为正式路径，并和在线安装共享同一套交互语言

对应页面：

- `views/main/OfflineImportViewIOS.swift`

工作项：

- [ ] 重构页面为正式导入入口，而不是技术工具页
- [ ] 页面结构统一为：header / 导入来源 / 内容编辑区 / 安装 CTA
- [ ] 清晰呈现 URL、本地、粘贴三类导入方式
- [ ] 保留“安装后切换到该配置”选项
- [ ] 减少零散说明块，把状态反馈嵌入主流程

完成标准：

- 用户把配置拿到手后，可以顺畅进入安装动作
- 离线导入和在线安装不会形成两种完全不同的体验

### F. 安装向导与执行反馈

目的：

- 把安装流程设计成“确认与执行面板”，而不是说明页

对应参考：

- Mac: `views/ProviderInstallWizard.swift`
- Mac: `core/ProviderInstallWindowManager.swift`
- iOS: `OfflineImportViewIOS.swift` 中的安装流，或其他 provider install flow

工作项：

- [ ] 抽出明确的安装步骤结构
- [ ] 当前步骤反馈可视化
- [ ] 技术细节折叠显示，不抢主流程
- [ ] 安装完成后保留自动切换能力
- [ ] 安装成功后尽量减少后续手动配置步骤

完成标准：

- 用户始终知道当前进行到哪一步
- 成功、失败、处理中三种状态都能在界面中清楚识别

### G. 卸载向导与危险操作降级

目的：

- 把卸载从简单 alert 升级为标准确认流，但不让它抢占页面主层级

对应参考：

- Mac: `views/ProviderUninstallWizard.swift`

对应 iOS：

- 已有卸载确认流则同步升级
- 如果没有，则新增标准卸载向导页

工作项：

- [ ] 卸载前说明简短明确
- [ ] 卸载步骤可视化或结构化呈现
- [ ] 危险按钮使用弱危险样式
- [ ] 避免红色主按钮成为页面视觉中心

完成标准：

- 危险操作清晰但不过度刺激
- 用户不会误把卸载看成主路径上的推荐动作

### H. 节点切换与测速页

目的：

- 让节点页回到实用型工具页，而不是概念展示页

对应页面：

- `views/main/OutboundGroupSectionView.swift`

工作项：

- [ ] 页面主体按“节点列表 + 延迟信息 + 切换操作”组织
- [ ] 每个节点行具备选中态
- [ ] 每个节点行展示节点名称
- [ ] 每个节点行展示地区或地址
- [ ] 每个节点行展示延迟值或“未测速”
- [ ] 每个节点行保留单节点测速入口
- [ ] 顶部保留“全部测速”

完成标准：

- 节点页能快速完成“看状态、测速、切换”三类动作
- 信息密度高，但层级仍然清晰

### I. 流量图与状态卡

目的：

- 把流量图从装饰图表改为真正的状态概览

对应页面：

- `views/main/StatusCardsView.swift`
- Home 页相关流量摘要区域

工作项：

- [ ] 顶部保留标题和短说明
- [ ] 中部重点展示上行合计 / 下行合计
- [ ] 下部展示增量 pills 和中型图表
- [ ] 控制图表高度，弱化网格线，保证曲线清晰
- [ ] 状态卡优先服务连接后场景，不抢首次引导入口

完成标准：

- 图表是辅助理解状态，不是视觉噱头
- 首页在未连接场景下不会被流量模块抢走注意力

### J. 设置与个人页统一收口

目的：

- 在主要使用路径完成后，把视觉语言扩展到设置与账户页

对应页面：

- `views/SettingsTabView.swift`
- `views/SettingsView.swift`
- `views/main/MeTabView.swift`

工作项：

- [ ] 统一 header、卡片、按钮和列表项样式
- [ ] 清理说明文案堆叠
- [ ] 统一危险操作和次级设置操作的层级
- [ ] 保持与首页、市场页、安装流同一套视觉语言

完成标准：

- 设置与个人页不会显得像另一套应用
- 全应用的层级、色彩、按钮语义保持一致


## 7. 页面映射参考

### 首页 / Dashboard

Mac 参考：

- `views/MenuSettingsPrimaryTabView.swift`

iOS 对应：

- `views/main/HomeTabView.swift`
- `views/main/StatusCardsView.swift`
- `views/main/ConnectionListView.swift`

### Market 推荐页

Mac 参考：

- `views/TrafficMarketView.swift`

iOS 对应：

- `views/main/MarketTabView.swift`

### Provider 市场管理页

Mac 参考：

- `views/ProviderMarketManagerView.swift`

iOS 对应：

- `views/main/ProviderMarketplaceView.swift`
- `views/main/InstalledProvidersView.swift`

### 离线导入

Mac 参考：

- `views/OfflineImportView.swift`

iOS 对应：

- `views/main/OfflineImportViewIOS.swift`

### 安装向导

Mac 参考：

- `views/ProviderInstallWizard.swift`
- `core/ProviderInstallWindowManager.swift`

iOS 对应：

- `OfflineImportViewIOS.swift` 中的安装流
- 其他 provider install flow

### 卸载向导

Mac 参考：

- `views/ProviderUninstallWizard.swift`

iOS 对应：

- 现有 provider 卸载确认流，或新增标准卸载向导页

### 节点切换与测速

Mac 参考：

- `views/MenuNodePickerWindowView.swift`

iOS 对应：

- `views/main/OutboundGroupSectionView.swift`

### 流量图与状态卡

Mac 参考：

- `views/MenuSettingsPrimaryTabView.swift` 中的 traffic card / detached traffic window

iOS 对应：

- `views/main/StatusCardsView.swift`
- Home 页相关 traffic summary


## 8. 行为逻辑要求

以下逻辑不是视觉建议，而是必须保留的行为要求。

- [ ] 安装完成后允许自动切换到该配置，并尽量默认开启
- [ ] 离线导入和在线安装遵循同一条主流程：先拿到配置，再执行安装
- [ ] 无配置时，首页主区必须聚焦“开始配置 / 导入配置 / 打开市场”
- [ ] 节点、测速、流量图等技术能力仅在已有 provider 且用户已进入可连接状态后提升权重


## 9. 实施顺序建议

建议按照下面顺序逐步推进，不要一次性全工程并改：

1. 先建立通用视觉基线和组件
2. 重构首页、Market、Offline Import 的首次可用路径
3. 重构 Provider Marketplace 和 Installed 管理
4. 再处理节点切换、连接列表、流量图等连接后工具页
5. 最后统一设置与个人页


## 10. 验收标准

当 iOS 迁移完成后，至少要满足以下标准：

- 新用户第一次打开应用时，知道从哪开始
- 导入 / 下载 / 安装之后能尽快进入可用状态
- Market / Installed / Offline Import / Node / Traffic 的视觉语言一致
- 危险操作不再抢主操作
- 技术信息有层级，而不是堆字
- 不靠大段说明文案解释界面
- 用户路径先于技术路径，首屏不再被工具模块主导


## 11. 本文档的用途

这份文档不是完整 diff，也不是历史变更记录，而是：

- 基于 `main...ue-refactor` 在 `MeshFluxMac` 的真实差异范围
- 提炼成适合 `MeshFluxIos` 的迁移工作计划
- 用于指导后续按阶段推进的 iOS 重构

后续对话建议直接以本文档为工作基线，按清单逐项推进，而不是一次性“全工程重做”。
