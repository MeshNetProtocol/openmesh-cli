# 回答你的 7 个问题（结论先行）

## 问题 1：Profile ↔ Provider 映射怎么做才合理？
建议把“供应商”当作一等实体（provider_id 为字符串），Profile 只是“某次安装后落到本地的可用配置”。要实现你要的“Dashboard 切换时做版本/哈希对比并同步”，必须有稳定映射：
- **profile_id → provider_id**：用于知道当前切换的是哪个供应商
- **provider_id → 已安装包 hash**：用于判断是否需要更新

在不改动现有 Profile 数据库 schema 的前提下，最稳妥且侵入最小的落地是：
- 用 `SharedPreferences` 增加一个 map（例如 `installedProviderIDByProfile: [String: String]`），key=profile_id(string)，value=provider_id。
- 另加一个 map（例如 `installedProviderPackageHash: [String: String]`），key=provider_id，value=package_hash。

这样 extension 侧也能同步读到 provider_id（SharedPreferences 在 extension 可用），就能做到后续的“按 provider 注入 force_proxy”。

## 问题 2：断开 VPN 连接重启 extension 是否可以解决？
可以。
- 你们当前的 macOS extension 已支持 `reload`（不一定全覆盖所有场景）。
- **断开/重连**是最强的生效手段：它会重新读取 profile config，并重新执行注入/初始化流程。
- 对于 `remote rule_set`（sing-box 自行下载 `.srs`）来说，第一次下载通常发生在启动期；如果你更新了 config 的 rule_set URL 或内容，断开/重连能确保它按新配置重新走一遍。

因此：当在线官方供应商更新或依赖同步完成后，UI 只需要提示用户“重连以立即生效”，并不需要做更多兜底。

## 问题 3：下载失败直接提示错误，不做兜底
认可。建议在产品行为上做到：
- 选中供应商时，同步失败 → 弹窗报错 → 不切换到该供应商（保持当前可用供应商）。
- Dashboard 切换时发现 hash 不一致 → 先尝试后台同步；失败 → 提示“更新失败，请切换其他供应商/稍后重试”，并保持当前运行配置。

## 问题 4：双官方供应商（本地保底 + 在线对照）
完全合理，而且能把你担心的“断网导致无法访问 AI”风险隔离干净。
- **provider_id = 0（逻辑概念）**：官方本地供应商（Local）。
  - 来源：仍然走现有 Xcode bundle 的 `default_profile.json` 安装逻辑（不改不动）。
  - 展示名：`官方本地供应商配置文件`
- **provider_id = 1（逻辑概念）**：官方在线供应商（Online）。
  - 来源：市场（D1 + Worker），remote + url。
  - 展示名：`官方供应商在线版本`

实现上建议用字符串 provider_id 来表达（避免和 profile_id 混淆）：
- `official-local`（等价于你说的 id=0）
- `official-online`（等价于你说的 id=1）

并在 UI 中明确标注：Local 是保底，Online 是市场版本。

## 问题 5：不用版本号，用内容 hash
认可，且建议“hash 作为唯一真相”，版本号可以彻底删掉。

推荐两级 hash：
- **provider_hash**：供应商“基本信息 + package_hash”的 hash（用于市场列表更新）。
- **package_hash**：供应商配置包的 hash（用于判断是否需要重新同步依赖）。

这样满足你的流程：
- market 全量更新只看 provider 列表（含 provider_hash/package_hash 摘要）。
- 选中/切换供应商时再请求 detail，对比 package_hash，不一致则同步。

## 问题 6：私人供应商 + 合规/安全后续
建议写入“后续工作”章节，不阻塞当前实施：
- provider.visibility：public | private
- public 才出现在市场浏览/推荐
- private 只能通过 `id` 精确搜索（搜索结果强提示风险）

实名认证/押金、紧急下线、文件级 sha256 校验、签名校验，都放到后续章节（作为运营期安全体系）。

## 问题 7：菜单栏市场只显示推荐 + 浏览更多
认可。
- 菜单栏弹窗：展示推荐供应商列表（官方可控）+ “浏览更多”按钮。
- 点击“浏览更多”打开独立窗口，提供分页/排序（时间、价格）/模糊搜索。

---

# 需要补充到文档的关键设计点（将写入文档）

## A. rule_set 的处理方式（remote + url）
- 主路径：供应商 config 采用 sing-box 标准 `type: remote` + `url`，由内核在 VPN 启动后自行下载 `.srs`。
- 明确约束：不做兜底。下载失败就报错并建议切换供应商。

## B. force_proxy 的按供应商隔离
- 现状：routing_rules 是全局单文件。
- 目标：按 provider_id 存放，例如：`AppGroup/MeshFlux/providers/<provider_id>/routing_rules.json`
- Extension 注入时根据当前 profile_id → provider_id 映射选择对应规则文件。

## C. Hash 驱动同步（替代 version）
- Market manifest：返回 providers 列表（含 `provider_hash`、`package_hash`、`price_per_gb_usd`、updated_at）。
- Provider detail：返回完整依赖清单（config URL、force_proxy URL、rule_set remote URLs），并返回 `package_hash`。
- 客户端本地存储：
  - `profile_id -> provider_id`
  - `provider_id -> installed_package_hash`

## D. 双官方供应商并行策略
- Local（保底）与 Online（市场）视为两个 provider。
- 明确：当前阶段不移除 Local。待 Online 稳定后，再删除/注销 Local 入口。

## E. D1 初始化 SQL（写入 official-online）
文档将给出一条 D1 初始化 SQL，写入 `official-online` 供应商记录：
- name=官方供应商在线版本
- package 使用 remote+url 的 rule_set
- config URL 指向 market worker 的 config endpoint

---

# 我将对文档做的更新（不动代码，先更新文档）
1. 把“版本号/updated_at”章节改为“hash 驱动同步”，保留 updated_at 仅作展示。
2. 增加“Profile ↔ Provider 映射”章节（SharedPreferences 两个 map）。
3. 增加“双官方供应商（Local/Online）策略”章节。
4. 补充“force_proxy 按 provider 隔离的文件路径与 extension 注入选择逻辑”。
5. 增加“私人供应商/合规/紧急下线/文件校验”为后续工作章节。
6. 调整 UI 章节：菜单栏只展示推荐 + 浏览更多；独立窗口 Grid + 详情页操作。

确认后我再实际修改文档文件内容。