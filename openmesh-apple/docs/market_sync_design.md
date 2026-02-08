# 流量市场版本同步与官方配置上云方案（修订版）

> 范围：MeshFluxMac / MeshFluxIos。
> 目标：市场侧提供可运营的供应商配置包；客户端支持版本对比与按需同步；“一模一样”以**行为一致**为准。

## 1. 需求与行为口径（你给的两条关键约束）

### 1.1 “一模一样”定义：行为一致
你当前希望的行为是：
- **force_proxy** 命中的目标：必须走 `proxy`（强制代理）。
- **geoip/geosite** 命中的目标：必须走 `direct`（直连）。
- 其它未命中流量：由本地开关决定（`direct` 或 `proxy`）。

现有客户端侧“其它未命中流量”的开关已存在：`SharedPreferences.unmatchedTrafficOutbound`（`direct`/`proxy`），VPN Extension 会把它写到 `route.final`。参考：
- [PacketTunnelProvider.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift) 中 `applyDynamicRoutingRulesToConfigContent` 对 `route.final` 的设置
- [SharedPreferences.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/VPNLibrary/Database/SharedPreferences.swift)

### 1.2 “全量更新”定义：仅更新供应商基本信息；依赖按需拉取
- **市场全量更新**：仅指“供应商基本信息列表”的全量更新（名称、描述、标签、价格、更新时间、hash 摘要等）。
- **供应商全量同步（按需）**：当用户选择某供应商时，再同步该供应商的**全部依赖与配置包**：
  - 供应商配置 JSON（sing-box config）
  - force_proxy（或更通用的 routing_rules.json/规则文件）
  - geoip/geosite 等 rule-set `.srs` 文件（以及未来可能的其它 JSON/资源）

并且：
- 不再使用版本号作为一致性判断，改用**内容 hash** 作为唯一真相（详情见 6.6）。
- Dashboard 切换到某供应商时，要进行一次 hash 请求并对比本地 hash：
  - 不一致则后台同步该供应商全部依赖；
  - 同步完成后提示用户“已更新，建议重连以立即生效”；若不重连，则保证**下次切换**一定使用新配置。
- 同步失败：直接提示错误，建议用户切换其它供应商；不做兜底。

## 2. 当前代码事实（作为设计对齐点）

### 2.1 配置文件落地与生效方式
- Profile 配置最终是一个 JSON 文件，写入 App Group：`.../configs/config_<id>.json`。
  - 路径定义： [FilePath.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/VPNLibrary/Shared/FilePath.swift)
  - 读写实现： [Profile+RW.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/VPNLibrary/Database/Profile%2BRW.swift)
- Extension 启动时读取“当前选中 Profile”的 config 内容，再做动态 patch：
  - 注入 routing_rules（force_proxy 规则来源）
  - 设置 route.final（未命中流量直连/代理）
  参考： [PacketTunnelProvider.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift)

### 2.2 routing_rules.json 目前是全局单文件
- `routing_rules.json` 目前是“App Bundle -> App Group”同步的单文件，并不是每个供应商独立。
  - 同步逻辑： [RoutingRulesStore.swift](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/SharedCode/RoutingRulesStore.swift)
  - 资源内容： [routing_rules.json](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/shared/routing_rules.json)

> 这意味着：为了支持“不同供应商有不同 force_proxy 内容”，后续实现阶段需要把 routing_rules 从“全局单文件”演进为“按供应商/按 Profile 生效”的规则文件。

## 3. 目标架构（服务端 + 客户端）

### 3.1 关键概念：Market / Provider / Provider Package
- **Market**：供应商列表（只包含基本信息与 hash 摘要）。
- **Provider**：一个流量供应商条目（包含 hash、更新时间、可用状态、摘要）。
- **Provider Package（供应商配置包）**：用户真正使用时要下载的“完整依赖集合”。
  - config.json（sing-box config）
  - force_proxy 规则文件（建议统一命名为 routing_rules.json 或 provider_rules.json）
  - rule-set 资源（geoip/geosite 的 `.srs`，以及未来扩展）

### 3.2 行为一致的规则组合（落地方式）
对任意供应商，都统一遵循三层路由优先级：
1) sniff
2) **force_proxy（走 proxy）**
3) **geoip/geosite（走 direct）**
4) final（由本地开关 direct/proxy 控制）

实现上：
- force_proxy：来自供应商的规则文件（Provider Package 的一部分），由 Extension 注入 route.rules（与当前机制一致，但需要“按供应商加载”）。
- geoip/geosite：由供应商的 config.json 自身声明 `route.rule_set`。
- final：继续由本地设置 `unmatchedTrafficOutbound` 控制。

### 3.3 rule-set（geoip/geosite）用 URL 下载还是随包同步？
sing-box 支持在 config 里用 `rule_set` 的 `type: remote` + `url` 来自动下载 `.srs`（并按 `update_interval` 自动更新）。这一点在我们现有的默认配置里也已经出现过（默认配置的 rule_set.url 指向网络地址）。参考：[default_profile.json](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/default_profile.json)。

以“减少故障点、简洁清晰”为宗旨，推荐采用**标准 sing-box 的 remote rule_set 方式**，原因是：
- 客户端不需要实现 `.srs` 下载/校验/落盘/更新逻辑（减少代码与边界条件）。
- 下载行为在 sing-box 内核内完成，能配合 `download_detour: proxy` 在 VPN 启动后通过代理拉取（更符合实际网络条件）。

需要注意的复杂度与策略：
- 若某供应商首次启用时本机完全无法联网（或代理尚不可用），remote rule_set 可能首次下载失败。为避免这类“首启卡住”的体验，建议将 rule_set 的 URL 指向**我们自己的 Worker/R2 镜像源**，并确保 `download_detour` 指向 `proxy`（即便 GitHub 被墙，也不依赖 GitHub）。
- 对“极端保守”的供应商（例如必须离线可用/在内核启动前就要规则），可以保留一条兼容路径：把 `.srs` 当作 Provider Package 文件由客户端同步到 App Group，然后 config 中用 `type: local` + `path: rule-set/...` 指向本地文件。但这应当是少数特例，而不是默认方案。

## 4. 服务端 API 设计（支持 market 与 provider hash）

> 注意：下述 API 是最终形态。数据库一步到位使用 **Cloudflare D1**（不提供 KV 过渡方案），文件与大对象放 **R2**。

### 4.1 市场清单（全量更新对象）
`GET /api/v1/market/manifest`
- 返回：market 级别版本信息 + 供应商基本信息列表（不含依赖文件清单/大内容）。
- 支持缓存：ETag + If-None-Match（304）。

返回示例（建议字段）：
```json
{
  "ok": true,
  "market_hash": "sha256:....",
  "market_updated_at": "2026-02-08T10:00:00Z",
  "providers": [
    {
      "id": "official-online",
      "name": "官方供应商在线版本",
      "description": "用于对照测试与市场链路验证：行为与 App 默认体验一致（force_proxy -> proxy；geoip/geosite -> direct；未命中流量由本地开关控制）",
      "tags": ["Official"],
      "author": "OpenMesh",
      "price_per_gb_usd": 0.0,
      "provider_updated_at": "2026-02-08T10:00:00Z",
      "provider_hash": "sha256:....",
      "package_hash": "sha256:....",
      "detail_url": "https://.../api/v1/providers/official-online"
    }
  ]
}
```

### 4.2 供应商详情（按需同步对象）
`GET /api/v1/providers/:id`
- 返回：供应商完整元数据 + 依赖文件清单（URL 为主，hash 用于一致性判断）。
- 这是用户“选中供应商”或“Dashboard 切换供应商时 hash 检查”的主要入口。

返回示例（建议字段）：
```json
{
  "ok": true,
  "provider": {
    "id": "official-online",
    "provider_updated_at": "2026-02-08T10:00:00Z",
    "provider_hash": "sha256:....",
    "name": "官方供应商在线版本",
    "description": "...",
    "tags": ["Official"],
    "author": "OpenMesh",
    "price_per_gb_usd": 0.0
  },
  "package": {
    "package_hash": "sha256:....",
    "files": [
      { "type": "config", "url": "https://..." },
      { "type": "force_proxy", "url": "https://..." },
      { "type": "rule_set", "tag": "geoip-cn", "mode": "remote_url", "url": "https://..." },
      { "type": "rule_set", "tag": "geosite-geolocation-cn", "mode": "remote_url", "url": "https://..." }
    ]
  }
}
```

### 4.3 （可选）快速 hash 检查接口
`HEAD /api/v1/providers/:id` 或 `GET /api/v1/providers/:id/hash`
- 只返回 provider_hash/package_hash/provider_updated_at/etag，Dashboard 切换时更省流量。

### 4.4 推荐供应商（给菜单栏/首页用）
`GET /api/v1/market/recommended?limit=6`
- 返回：推荐供应商的基本信息列表（同 manifest 里的 provider 字段子集）。
- 用途：菜单栏空间有限时，仅展示“当前在用 + 推荐若干个 + 打开市场按钮”。推荐逻辑可由服务端控制（例如运营配置）。

### 4.5 市场浏览（独立窗口：分页/排序/搜索）
`GET /api/v1/market/providers?page=1&page_size=24&sort=time&order=desc&q=mesh`
- 返回：分页列表（用于独立窗口 Grid 展示）。
- sort 支持：`time` | `price`（price 即 `price_per_gb_usd`）。
- q 支持：按供应商名称模糊搜索（服务端实现 contains/like）。

## 5. 服务端存储建议（把配置从代码里移出去）

### 5.1 推荐组合：D1 + R2（可运营）
- **D1**：存 providers 元数据（id、name、desc、tags、price_per_gb_usd、provider_updated_at、provider_hash、package_hash、visibility、status 等）
- **R2**：存配置包文件（config.json / routing_rules.json / *.srs / 其它 JSON）（如果 rule_set 采用 remote + url，则 `.srs` 可直接由 URL 提供）
- Worker 负责：
  - market manifest（从 D1 读 providers，拼装列表）
  - provider detail（从 D1 查依赖列表，返回 URL + package_hash）

### 5.2 D1 初始化（写入一条“官方供应商（对照测试）”记录）
目的：在不修改客户端“Xcode 资源默认配置安装逻辑”的前提下，往 D1 写入一条官方供应商记录，用于对比测试“市场下载的官方供应商”在行为上与“App 内置官方供应商”一致。

现状确认（以 MeshFluxMac/MeshFluxIos 为讨论范围）：
- 默认配置文件在 App Bundle 内是 [default_profile.json](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/default_profile.json)。
- 该默认配置的 `route.rule_set` 当前已使用 `type: remote` + `url` 的方式（由 sing-box 自行下载 `.srs`），并支持 `download_detour: proxy` 与 `update_interval`。这意味着在“市场侧”我们也可以采用 **remote + url**，避免客户端实现 `.srs` 下载与缓存逻辑。
- 仓库中存在 `openmesh-apple/shared/rule-set/*.srs`，主要用于脚本安装/开发辅助或系统扩展场景；MeshFluxMac/MeshFluxIos 的默认 profile 本身并不依赖把 `.srs` 作为 Xcode 资源文件打包进 App。

为满足“数据库里记录的是 remote + url，而不是资源文件”，建议 D1 表中用 `package_json`（JSON 字符串）保存依赖文件清单（包括 rule-set 的 remote url）。

下面是一条用于初始化官方在线供应商记录的 SQL（假设 D1 存在 `providers` 表，且包含这些列；其中 URL 以你的 Worker 域名为基准，可按实际路径调整）。

```sql
INSERT INTO providers (
  id,
  name,
  description,
  tags_json,
  author,
  price_per_gb_usd,
  provider_updated_at,
  provider_hash,
  package_hash,
  visibility,
  status,
  package_json
) VALUES (
  'official-online',
  '官方供应商在线版本',
  '用于对照测试：行为与 App 内置默认配置一致（force_proxy -> proxy；geoip/geosite -> direct；未命中流量由本地开关控制）',
  '["Official","Online"]',
  'OpenMesh',
  0.0,
  '2026-02-08T00:00:00Z',
  'sha256:REPLACE_WITH_PROVIDER_HASH',
  'sha256:REPLACE_WITH_PACKAGE_HASH',
  'public',
  'enabled',
  '{
    "config": {
      "mode": "download",
      "url": "https://openmesh-api.ribencong.workers.dev/api/v1/config/official-online"
    },
    "force_proxy": {
      "mode": "download",
      "url": "https://openmesh-api.ribencong.workers.dev/api/v1/rules/official-online/routing_rules.json"
    },
    "rule_sets": [
      {
        "tag": "geoip-cn",
        "mode": "remote_url",
        "url": "https://openmesh-api.ribencong.workers.dev/assets/rule-set/geoip-cn.srs"
      },
      {
        "tag": "geosite-geolocation-cn",
        "mode": "remote_url",
        "url": "https://openmesh-api.ribencong.workers.dev/assets/rule-set/geosite-geolocation-cn.srs"
      }
    ]
  }'
);
```

重要约束（再次强调）：客户端侧“内置官方供应商”的创建逻辑必须保持不变（仍使用 bundle 里的 default_profile.json 安装，作为永远可用的保底配置）。市场侧的这条 D1 记录仅用于对照测试与验证市场链路，不替代本地保底机制。

为避免概念混淆，本方案明确把“官方供应商”拆成两个不同的 provider：
- `official-local`：官方本地供应商配置文件（来自 Xcode 资源逻辑；现阶段不动）
- `official-online`：官方供应商在线版本（来自流量市场；用于对照测试与未来替代）

## 6. 客户端同步策略（严格符合你“全量更新/按需同步”的定义）

### 6.1 本地持久化（建议都放 App Group，方便主 App/VPN Extension/未来共享）
- `AppGroup/MeshFlux/market/market_manifest.json`
- `AppGroup/MeshFlux/market/providers_cache.json`
- `AppGroup/MeshFlux/market/providers/<provider_id>/provider_detail.json`
- `AppGroup/MeshFlux/market/providers/<provider_id>/files/...`（下载的依赖文件缓存）

并新增偏好项（示意）：
- last_market_hash / last_market_etag
- profile_id -> provider_id
- provider_id -> installed_package_hash
- provider_id -> last_sync_at

### 6.2 进入流量市场：只做 market 级全量更新
1) 请求 `/market/manifest`（带 If-None-Match）
2) 304：直接用缓存展示
3) 200 且 market_hash 或 updated_at 变化：
   - 覆盖本地 providers 列表缓存
   - UI 刷新

### 6.3 用户在市场“选中/安装”某供应商：做供应商包的按需全量同步
1) 请求 `/providers/:id` 获取 package_hash + 依赖文件列表
2) 弹出等待界面（进度条/文件数）
3) 下载并落地依赖文件（至少包含：config.json、force_proxy 规则文件）
4) 写入 App Group（按约定目录）
5) 创建 Profile config 文件（`configs/config_<nextId>.json`）并建立 Profile 记录
6) 保存映射：profile_id -> provider_id；并记录 provider_id -> installed_package_hash
7) 选中该 Profile
8) 若下载失败：直接提示错误并终止切换，建议用户选择其它供应商（不做兜底）

### 6.4 Dashboard 切换到某供应商：先做 hash 检查，再决定是否后台同步
触发点：用户切换 Profile（或你未来的“供应商切换”入口）。
1) 根据当前 Profile 找到 provider_id（或 provider_type=local/offical 等）
2) 请求 provider hash（detail 或 hash endpoint）
3) 若 package_hash 不一致：
   - 后台下载并覆盖该 provider 的依赖文件（不强制立即重连）
   - 下载成功后提示“已更新，重连可立即生效”；若不重连，则保证下次切换使用新配置
4) 若下载失败：直接提示错误，建议用户切换其它供应商（不做兜底）

补充说明：断开 VPN 并重新连接（重启 extension）可以确保读取到最新 profile config 并按新规则生效。

### 6.5 客户端 UI 设计（菜单栏 + 独立窗口）
由于菜单栏弹窗空间有限，不适合承载“供应商市场”的复杂交互，建议拆为两层：

**菜单栏弹窗（轻量）**
- 展示：官方推荐供应商列表（来自 `/market/recommended`，可控且数量少）。
- 增加一个“浏览更多”按钮，用于打开独立窗口。

**独立窗口（完整市场）**
- 通过菜单栏按钮打开一个独立窗口，用于完整的供应商浏览与选择。
- 顶部控件：
  - 排序：时间 / 价格
  - 分页：上一页 / 下一页（或页码）
  - 查询：输入框 + 查询按钮（按供应商名称模糊搜索）
- 默认排序：时间（最新优先）。

**供应商展示方式（Grid）**
- 以 Grid 卡片展示基本信息（名称、简介、tags、价格、更新时间）。
- 卡片本身不放“选中/使用”按钮。
- 用户点击卡片进入“供应商详情页”（同窗口内 push 或 sheet），在详情页展示：配置说明、包含的规则/规则集摘要、hash 信息、价格与最终的“使用/安装/切换”按钮。

### 6.6 Hash 驱动同步（替代版本号）
本方案中“是否需要更新/同步”的唯一依据是 hash：
- `provider_hash`：供应商基本信息（含 package_hash、价格等）hash，用于判断市场列表是否变化。
- `package_hash`：供应商配置包（config URL + force_proxy URL + rule_set remote URLs 等）hash，用于判断是否需要重新同步依赖。

客户端本地至少持久化：
- `profile_id -> provider_id` 映射（用于 Dashboard 切换时定位供应商）
- `provider_id -> installed_package_hash`（用于判断是否需要更新）

失败处理原则：只提示错误、不兜底；用户可切换其它供应商或稍后重试。

## 7. 官方供应商（行为一致版）的内容来源与生成方式

为满足“开发期永远有一个可用保底”的要求，本方案把官方供应商拆分为两个独立 provider：

- `official-local`（概念 id=0）：官方本地供应商配置文件
  - 来源：仍然使用 Xcode 资源的 [default_profile.json](file:///Users/hyperorchid/MeshNetProtocol/openmesh-cli/openmesh-apple/MeshFluxMac/default_profile.json) 安装逻辑创建 Profile（现阶段不动、不改、不删除）
  - 目的：永远可用的保底配置，防止市场链路/实现不完整导致“无法使用 VPN 进而无法访问 AI”
- `official-online`（概念 id=1）：官方供应商在线版本
  - 来源：流量市场（D1 + Worker）
  - 目的：用于对照测试与未来替代本地逻辑；当在线版本稳定后，再逐步下线/移除 `official-local` 的入口与代码

行为一致要求（两者都必须满足）：
- force_proxy 命中 -> proxy
- geoip/geosite 命中 -> direct
- 未命中 -> 由本地开关决定（SharedPreferences.unmatchedTrafficOutbound）

## 8. 实施步骤（按风险/前置条件排序）

### 8.0 开工前置条件（先做，避免走弯路）
- 固定 provider_id 规则：`official-local`（保底）与 `official-online`（市场）为两个不同 provider；现阶段不动 `official-local` 的 Xcode 资源安装逻辑。
- 固定 Profile ↔ Provider 映射方案：至少支持 `profile_id -> provider_id` 与 `provider_id -> installed_package_hash` 的持久化（用于 Dashboard 切换时判断是否需要更新）。
- 固定 force_proxy 的按 provider 隔离方案：routing_rules 不再是全局单文件，必须能按 provider 加载与注入，避免不同供应商互相污染。
- 固定 hash 计算口径：明确 `provider_hash` 与 `package_hash` 的输入字段与 canonical 规则（避免“内容没变但 hash 变了”的假更新）。
- 固定 D1 表结构：一步到位（含 price、visibility、status、provider_hash、package_hash、package_json 等），并写入 `official-online` 初始记录用于对照测试。
- 确认 remote rule_set 的可用性策略：默认采用 sing-box `type: remote + url`，URL 指向我们自己的 Worker/R2 镜像源；失败按“报错提示切换/重连”处理，不做兜底。

### Phase 1：服务端打底（D1 + API）
- 建表（D1）：providers（含 hash、price、visibility、status、package_json）
- 初始化数据：写入 `official-online`（在线官方供应商）记录（remote + url）
- 实现 API：
  - `/api/v1/market/manifest`（market_hash + providers 摘要，ETag）
  - `/api/v1/providers/:id`（provider_hash/package_hash + package files 清单）
  - `/api/v1/providers/:id/hash` 或 `HEAD /api/v1/providers/:id`（可选，用于 Dashboard 快速检查）
  - `/api/v1/market/recommended`、`/api/v1/market/providers`（独立窗口分页/排序/搜索）

### Phase 2：发布工具链（内容生成与 hash 产出）
- 生成“官方在线版本”所需内容（config + force_proxy + rule_set URL 列表）
- 计算 `package_hash/provider_hash/market_hash` 并写入 D1
- 上传配置包文件到 R2（至少 config 与 force_proxy；rule_set 走 remote url）

### Phase 3：客户端同步（最小闭环：安装与切换）
- 市场列表：按 `market_hash/ETag` 更新 providers 基本信息（不拉依赖）
- 供应商详情：拉 `/providers/:id`，对比 `package_hash`，不一致则展示等待界面并同步依赖（至少 config + force_proxy）
- 写入映射：`profile_id -> provider_id` 与 `provider_id -> installed_package_hash`
- Dashboard 切换：先查 hash；不一致则后台同步；成功提示“重连以立即生效”；失败提示错误并建议切换其它供应商

### Phase 4：Extension 注入（确保行为一致）
- 根据当前 profile 反查 provider_id
- 从 provider 对应目录读取 force_proxy 规则并注入（优先级在 sniff 之前）
- final 仍由本地开关控制（unmatchedTrafficOutbound）

### Phase 5：UI 完整化（菜单栏 + 独立窗口）
- 菜单栏：只显示官方推荐 + “浏览更多”按钮
- 独立窗口：Grid + 分页/排序（时间/价格）/模糊搜索 + 详情页安装按钮

### Phase 6：逐步下线本地保底（最后做）
- 当 `official-online` 长期稳定可用后，再逐步移除/注销 `official-local` 的入口与代码

---

# 下一步（等待你确认）
确认点已被你明确：
- “一模一样”= 行为一致 ✅
- market 全量更新仅限供应商列表 ✅
- provider 选择/切换触发按需同步 provider package ✅

我会在你确认这份方案后，再开始按 Phase 1~5 逐步实现，并且实现时会重点处理“每个供应商独立的 force_proxy + geoip/geosite 依赖”的落地与版本控制。

## 9. 后续工作（不阻塞当前实施）
### 9.1 私人供应商（Private Provider）
- provider 增加 `visibility`：public | private
- public：可在市场浏览/推荐中展示
- private：不展示，但允许通过 id 精确搜索；加载前给出足够风险提示

### 9.2 合规与运营机制
- 公共供应商：实名认证、缴纳押金、价格字段规范化、可运营的推荐位策略

### 9.3 安全与应急
- 文件级 sha256 校验（除 package_hash 外的更细粒度校验）
- 供应商紧急下线（status=disabled，全端立即不可用）
- 配置包签名校验（防投毒/防篡改）
