# 远程规则集（geoip-cn）验证与“观察”逻辑说明

## 1. 如何确认 geoip-cn 已下载并生效

### 1.1 配置前提

- **profile 中需包含**：
  - `route.rule_set` 里有一条 `type: "remote"`、`tag: "geoip-cn"`、`url: "https://raw.githubusercontent.com/..."` 的条目。
  - `experimental.cache_file.enabled: true`（用于缓存远程规则，否则每次启动都重新下载）。
- **注意**：macOS **系统扩展**（`vpn_extension_macx`）不会访问该 URL，会使用 **bundle 内的 geoip-cn.srs** 或移除该规则集，见 `vpn_extension_macx/PacketTunnelProvider.swift` 中 `buildConfigContent()`。

### 1.2 通过日志确认

sing-box 核心在加载/更新 remote rule-set 时会打日志（见 `sing-box/route/rule/rule_set_remote.go`）：

- **Info 级别**（`log.level: "info"` 即可看到）：
  - 首次下载成功：`updated rule-set geoip-cn`
  - 定时更新未变更：`update rule-set geoip-cn: not modified`
- **Debug 级别**（需 `log.level: "debug"`）：
  - 开始拉取：`updating rule-set geoip-cn from URL: https://raw.githubusercontent.com/...`

**操作建议**：

1. 在 profile 里确认 `"log": { "level": "info" }`（或临时改为 `"debug"` 看更多细节）。
2. 启动 VPN（App 扩展或 iOS），在 **扩展的日志** 里查找上述字符串。  
   - macOS App 扩展：日志可能在系统/Console 中按进程筛选，或我们重定向的 `Library/Caches/stderr.log`（在 App Group 的 cache 目录下）。
3. 若看到 `updated rule-set geoip-cn` 或 `update rule-set geoip-cn: not modified`，说明已下载或已使用缓存并生效。

### 1.3 通过缓存文件确认

- 当 `experimental.cache_file.enabled: true` 时，核心会把远程规则集写入 **bbolt 缓存**。
- 默认文件名为 `cache.db`，路径由 sing-box 的 **basePath** 决定：
  - **macOS App 扩展**：basePath = App Group 容器根路径，即 `cache.db` 在 App Group 目录下。
  - **iOS**：同理在 App Group 目录下。
- 若该路径下存在 `cache.db` 且 VPN 曾成功启动，通常说明至少曾成功加载过规则（包括 geoip-cn）；可配合日志确认。

### 1.4 若“感觉没生效”的常见原因

- **download_detour: "proxy"**：首次下载走的是名为 `proxy` 的 outbound。若此时代理不可用（未连上、服务器不可达等），首次 `fetch` 会失败，启动可能报错或规则集为空。
- **网络/GFW**：无法访问 `raw.githubusercontent.com` 且无可用代理时，下载会失败。
- **使用的是 macOS 系统扩展**：不会请求该 URL，而是用本地 bundle 或去掉该规则集，这是预期行为。

---

## 2. “观察这个链接内容”的逻辑说明

我们**没有**“观察远程 URL 内容是否变化”的独立逻辑；和规则相关的有两块：

### 2.1 本地目录观察（FileSystemWatcher）

- **位置**：`vpn_extension_ios`、`vpn_extension_macx` 中的 `FileSystemWatcher`。
- **观察对象**：**App Group 共享目录**（`sharedDataDirURL`），例如 `routing_rules.json`、config 等**本地文件**的变更。
- **行为**：当检测到该目录下文件变化时，触发 `scheduleReload` → `reloadService`，即**重新读取配置并重启 box 服务**。
- **结论**：这是“观察**本地**配置/规则文件变化并热重载”，**不是**观察远程 geoip URL 的内容。

### 2.2 远程规则集的定时更新（update_interval）

- **实现位置**：`sing-box/route/rule/rule_set_remote.go` 中的 `RemoteRuleSet`。
- **行为**：根据配置中的 `update_interval`（如 `"1d"`），在服务运行期间**周期性**调用 `fetch()` 重新请求该 URL，若有更新则替换规则并写回缓存。
- **结论**：对“该链接内容”的“观察”是**按固定间隔重新下载**，由 sing-box 核心完成，我们 App/Extension 只负责传入包含 `rule_set` 的 config，不单独实现“监控 URL 内容”的逻辑。

若要“确认远程规则已按间隔更新”，可配合 **info 日志**：在运行满一个 `update_interval` 后，若看到 `updated rule-set geoip-cn` 或 `update rule-set geoip-cn: not modified`，即说明已执行过对该 URL 的再次检查。

---

## 3. 如何测试 geoip-cn.srs 是否生效

### 3.1 分步测试建议

1. **确认规则集已加载**  
   - 启动 VPN 后，在扩展日志中搜索：`updated rule-set geoip-cn` 或 `update rule-set geoip-cn: not modified`。  
   - 若看到其中一条，说明远程 geoip-cn 已下载或使用缓存，规则集已加载。

2. **确认下载/缓存路径**  
   - 若启用 `experimental.cache_file.enabled: true`，检查 App Group 目录下是否存在 `cache.db`（扩展的 basePath）。  
   - 存在且 VPN 曾成功启动，可佐证规则集曾成功写入缓存。

3. **行为验证**  
   - 访问仅在中国大陆解析的站点（如 baidu.com、bilibili.com），确认流量未走代理（例如在代理侧或出口侧看不到对应请求）。  
   - 当前配置中，geoip-cn 用于 TUN 的 `route_exclude_address_set`：命中 geoip-cn 的 IP 会从 TUN 中排除，由系统直连，不会进入 sing-box 的规则匹配流程。

### 3.2 若“没处理好”可重点排查

- **download_detour: "proxy"**：首次拉取走 `proxy` outbound，若此时代理不可用，会拉取失败，启动报错或规则集为空。  
- **网络**：本机或代理无法访问 `raw.githubusercontent.com` 时也会失败。  
- **平台**：macOS 系统扩展（`vpn_extension_macx`）不会请求该 URL，会使用 bundle 内 geoip-cn.srs 或移除该规则集。

---

## 4. “请求命中 geoip-cn 规则”会有日志吗？

### 4.1 当前配置下的情况

在 **default_profile** 里，geoip-cn **只**出现在两处：

- **`route.rule_set`**：定义远程规则集（从 URL 下载）。
- **TUN 的 `route_exclude_address_set: ["geoip-cn"]`**：用于生成“排除列表”，决定哪些目标 IP **不**进 TUN（即直连）。

也就是说，**没有任何一条 `route.rules` 使用 `rule_set: ["geoip-cn"]`**。  
因此：

- 命中 geoip-cn 的流量是在 **TUN 层**被排除的（不进入隧道），不会走到 **路由规则**（`route.rules`）的逐条匹配。
- sing-box 在 **规则匹配** 时才会打“某条规则命中”的日志（见下），而 TUN 排除是内核/路由表层面的行为，**没有**“这个包被 route_exclude_address_set 命中”的逐包/逐连接日志。

所以：**在当前配置下，一个请求因为“属于 geoip-cn”而被直连时，不会有对应的命中日志。**

### 4.2 规则命中的日志级别（若走 route.rules）

当流量**确实经过** `route.rules` 的匹配时（例如某条规则使用了 `rule_set: ["geoip-cn"]`），sing-box 会在**规则命中**时打日志（见 `sing-box/route/route.go`）：

- **仅当 `log.level` 为 `"debug"` 时**才会输出，例如：  
  `match[规则下标] rule_set=geoip-cn => direct`（或对应 action）。
- **`log.level: "info"` 时**：不会打每条规则命中的日志。

因此：  
- 想要看到“**这条连接命中了某条规则（包括 geoip-cn）**”的日志 → 需要把 **`log.level` 设为 `"debug"`**，并且该流量必须经过一条引用 `rule_set: ["geoip-cn"]` 的 **route 规则**。

### 4.3 若希望“命中 geoip-cn 就有日志”

当前配置没有在 `route.rules` 里使用 geoip-cn，所以不会有“命中 geoip-cn”的规则日志。若你**希望**在日志里看到“某连接因 geoip-cn 命中而走了 direct”：

1. 在 **`route.rules`** 里增加一条使用 geoip-cn 的规则（例如放在靠前位置，按需调整顺序）：  
   ```json
   {
     "rule_set": ["geoip-cn"],
     "action": "direct"
   }
   ```
2. 将 **`log.level`** 设为 **`"debug"`**。  
3. 之后，当连接命中这条规则时，会看到类似：  
   `match[N] rule_set=geoip-cn => direct`。

注意：一旦在 `route.rules` 里加了这条规则，**命中 geoip-cn 的流量会先被这条规则处理**；若你同时保留了 TUN 的 `route_exclude_address_set: ["geoip-cn"]`，两者会一起生效（排除列表 + 规则 direct），行为上通常一致，只是多了一层在路由规则里的显式匹配，便于用 debug 日志观察。
