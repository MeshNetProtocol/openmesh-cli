# Android 已安装供应商界面同步工作规划 (Synchronization Plan)

本计划旨在将 iOS 工程 (`openmesh-apple`) 中的 **"已安装供应商 (Installed Providers)"** 界面的 UI 和逻辑同步到 Android 工程 (`openmesh-android`)。

## 目标 (Goals)
1. **UI 对齐**：实现与 iOS 一致的深蓝/清新风格，包含顶部状态 Chip、搜索栏、以及信息丰富的列表项。
2. **逻辑增强**：支持列表搜索过滤、本地/远程 Hash 对比显示、更新检测集成。
3. **卸载向导**：将简单的删除对话框替换为分步进度的“卸载向导”界面。

---

## 工作拆分 (Task Breakdown)

### 1. 基础资源准备 (Resources & Styles)
*   **1.1 定义颜色与样式**：在 `res/values/colors.xml` 中确保有与其 iOS 主题对应的 HSL 色彩（meshBlue, meshAmber, meshRed, meshMint 等）。
*   **1.2 准备 Drawables**：创建 Chip 的背景（圆角边框）、搜索框背景、以及 monospaced 字体支持。

### 2. 列表项布局 (`item_installed_provider.xml`)
*   **2.1 整体结构**：水平布局，左侧信息区，右侧动作区。
*   **2.2 信息区内容**：
    *   第一行：显示供应商名称 + 动态状态 Chip (如: `Update`, `Offline`, `Init`)。
    *   第二行：显示 `providerID` (使用 Monospace 字体，省略号截断)。
    *   第三行：显示 `Local Hash` 和 `Remote Hash` 对比 (Monospace 字体)。
    *   第四行（可选）：显示 `pendingRuleSetTags`。
*   **2.3 动作区内容**：
    *   如果存在更新：显示“更新配置”按钮。
    *   右侧显示一个 Chevron 图标表示可进入详情。

### 3. 主对话框布局 (`dialog_installed_providers.xml`)
*   **3.1 头部区域**：
    *   三个状态 Chip：`已安装 n` (Blue), `可更新 n` (Amber), `离线 n` (Red)。
    *   搜索框：实现搜索图标 + 清除按钮风格。
    *   刷新按钮：圆形同步图标。
*   **3.2 内容区域**：
    *   使用 `RecyclerView` 展示已安装列表。
    *   支持 `Empty View` (暂无匹配供应商)。
*   **3.3 顶部标题栏**：包含标题“已安装”和关闭按钮。

### 4. 卸载向导布局与逻辑 (`dialog_provider_uninstall_wizard.xml`)
*   **4.1 布局设计**：参照 iOS `ProviderUninstallWizardView`。
    *   顶部显示要卸载的供应商 ID 和名称。
    *   中间是分步进度列表（Validate, Stop, Cleanup, Finalize）。
    *   底部是“开始卸载”/“完成”/“关闭”按钮。
*   **4.2 向导控制器**：
    *   调用 `ProviderUninstaller.uninstall` 接口。
    *   根据回调实时更新界面上的步骤状态（Pending, Running, Success, Failure）。

### 5. 核心逻辑实现 (`InstalledProvidersDialog.kt`)
*   **5.1 数据加载**：
    *   从 `ProviderStorageManager` 获取本地已安装 ID。
    *   从 `MarketCache` 获取对应的服务器 Provider 信息（用于 Hash 对比）。
    *   从 `ProviderPreferences` 获取更新可用状态。
*   **5.2 搜索过滤**：实现对名称、ID、Hash、Tags 的关键字匹配。
*   **5.3 事件处理**：
    *   点击“更新配置”：触发 `ProviderInstallWizardDialog`。
    *   点击列表项：触发 `ProviderDetailDialog`。
    *   详情页中点击“卸载”：触发 `ProviderUninstallWizardDialog`。

---

## 自检清单 (Self-check List)
- [ ] UI 是否实现了 iOS 的卡片悬浮感和圆角风格？
- [ ] 搜索框输入时，列表是否能实时过滤？
- [ ] 当服务器 Hash 与本地不一致时，是否正确显示 `Update` Chip 和更新按钮？
- [ ] 卸载向导是否能正确显示每个步骤的运行状态？
- [ ] 卸载完成后，主界面的供应商选择状态是否已重置（如果卸载的是当前选中的）？
- [ ] 搜索、更新、卸载过程中的 Loading 状态是否完整？

## 其他 AI 注意事项 (Notes for AI)
*   **数据一致性**：逻辑层必须与 `UpdateChecker` 和 `ProviderPreferences` 紧密集成，确保角标和列表状态同步。
*   **并发处理**：刷新逻辑应注意协程作用域，避免在 Dialog 关闭后继续回调。
*   **Hash 显示**：Hash 字符串很长，UI 上必须做中间截断处理（如 `abc12...xyz78`）。
