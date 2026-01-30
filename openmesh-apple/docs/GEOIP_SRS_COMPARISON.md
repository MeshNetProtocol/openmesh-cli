# geoip-cn.srs 处理逻辑：openmesh-apple vs sing-box SFM

## 结论摘要

- **Mac 应用级**（vpn_extension_macos）**不会**对 config 做任何修改，`route.rule_set` 里的 `geoip-cn` URL 会**原样**传给 libbox，与 sing-box SFM Extension 行为一致。
- 与 sing-box 的差异只有 **LibboxSetup 传参用 `.path` 还是 `.relativePath`**，在 macOS App Group 下通常等价，可改为 `.relativePath` 以完全对齐。
- **`download_detour`**：表示「用哪个 outbound 去下载规则集」。`"proxy"` = 走代理下载，`"direct"` = 直连下载。在直连无法访问 raw.githubusercontent.com 的环境下，必须用 `"proxy"`；改为 `"direct"` 会导致下载失败。sing-box 官方示例也是 `"proxy"`。
- **失败行为**：sing-box 核心在 `rule_set_remote.go` 中，**首次** fetch 失败会直接 `return error`，导致 service Start 失败（VPN 连不上），不会静默「规则集为空继续跑」。因此若 VPN 能连上，规则集要么来自缓存要么首次下载已成功；国内仍走代理/微信慢需要从**规则顺序、route_exclude_address_set 是否生效、缓存是否异常**等方向排查。

---

## 1. 我们（openmesh-apple）的处理

### 1.1 Mac 应用级 extension（vpn_extension_macos）

| 项目 | 实现 |
|------|------|
| Config 来源 | `resolveConfigContent()` → `selectedProfileID` → `ProfileManager.get()` → `profile.read()`，无 profile 时用 bundled `default_profile.json` |
| 是否修改 config | **不修改**。直接 `OMLibboxNewService(configContent, platform, &err)`，整段 JSON 原样传给 libbox |
| rule_set / geoip-cn | 未做任何替换、删除或重排，`default_profile.json` 里的 `route.rule_set`（含 geoip-cn 的 url）会完整进入核心 |

相关代码：`vpn_extension_macos/PacketTunnelProvider.swift`  
- 第 114 行：`let configContent = try self.resolveConfigContent()`  
- 第 116 行：`OMLibboxNewService(configContent, platform, &serviceErr)`  
- `resolveConfigContent()` 只做 profile.read() 或读 bundled default_profile，不解析/改写 JSON。

### 1.2 LibboxSetup 路径（vpn_extension_macos）

```swift
setup.basePath = baseDirURL.path        // sharedDirectory 的 .path
setup.workingPath = workingDirURL.path   // FilePath.workingDirectory 的 .path
setup.tempPath = cacheDirURL.path       // FilePath.cacheDirectory 的 .path
```

即：我们传的是 **绝对路径**（`URL.path`）。

### 1.3 系统扩展（vpn_extension_macx）—— 仅作对比

**仅系统扩展**会在 `buildConfigContent()` 里改 rule_set：把 remote geoip-cn 换成 bundle 内 `geoip-cn.srs` 或删掉该规则集（见 `vpn_extension_macx/PacketTunnelProvider.swift` 约 346–378 行）。  
你当前测的是 **Mac 应用级**，走的是 vpn_extension_macos，**不会**执行这段逻辑。

---

## 2. sing-box SFM 的处理

### 2.1 Extension（Library/Network/ExtensionProvider.swift）

| 项目 | 实现 |
|------|------|
| Config 来源 | `ProfileManager.get(selectedProfileID)` → `profile.read()` |
| 是否修改 config | **不修改**。直接 `LibboxNewService(configContent, platformInterface, &error)` |
| rule_set / geoip-cn | 不处理，由核心按 config 下载/缓存 |

与我们在应用级上的逻辑一致：都是「Profile → read() → 整段 config 交给 libbox」。

### 2.2 LibboxSetup 路径（sing-box ExtensionProvider）

```swift
options.basePath = FilePath.sharedDirectory.relativePath
options.workingPath = FilePath.workingDirectory.relativePath
options.tempPath = FilePath.cacheDirectory.relativePath
```

即：sing-box 传的是 **`.relativePath`**。  
在 macOS 上，对 App Group 的 `containerURL(...)` 得到的 URL 通常**没有** baseURL，此时 `relativePath` 与 `path` 会相同（都是绝对路径）。因此多数情况下行为一致，但为与 SFM 完全一致，建议我们改为使用 `.relativePath`。

---

## 3. 差异小结

| 维度 | openmesh-apple（Mac 应用级） | sing-box SFM |
|------|------------------------------|--------------|
| 是否修改 config / rule_set | 否 | 否 |
| geoip-cn URL 是否传入核心 | 是（原样） | 是 |
| LibboxSetup basePath 等 | `.path`（绝对） | `.relativePath`（此处通常也是绝对） |

没有「我们没传 rule_set 或把 URL 改掉」这类本质差异；**srs 文件是否真正被加载并生效，取决于核心的下载与缓存**。

---

## 4. App Group 实际配置与 sing-box 的 rule_set / rules 顺序对比

**数据来源**：  
- 我们：`~/Library/Group Containers/group.com.meshnetprotocol.OpenMesh/configs/config_1.json`（extension 实际读取的 profile）  
- sing-box：`sing-box/docs/migration.zh.md` 中「迁移 GeoIP 到规则集」的 route 示例  

### 4.1 rule_set 数组

| 项目 | 我们（config_1.json） | sing-box 迁移示例 |
|------|------------------------|-------------------|
| 内容 | 仅 `geoip-cn`（remote，download_detour: proxy） | `geoip-cn` + `geoip-us` |
| 顺序 | rule_set 在 route 内、rules 之前 | 同左 |

**结论**：rule_set 定义顺序一致，我们只有 geoip-cn 一项，无差异。

### 4.2 route.rules 顺序（重要差异）

**我们（config_1.json）**：

1. `{ "action": "sniff" }`
2. 大量 `{ "domain": [...], "outbound": "proxy" }` 规则
3. `{ "action": "hijack-dns", "protocol": "dns" }`  
**没有**任何一条「`rule_set` geoip-cn ⇒ direct」的规则；国内直连只依赖 TUN 的 `route_exclude_address_set: ["geoip-cn"]`。

**sing-box 迁移示例**：

1. `{ "ip_is_private": true, "outbound": "direct" }`
2. **`{ "rule_set": "geoip-cn", "outbound": "direct" }`** ← 显式「国内直连」
3. `{ "rule_set": "geoip-us", ..., "outbound": "block" }`
4. 其他规则…

**结论**：我们在 **route.rules 里缺少「rule_set geoip-cn ⇒ direct」**，且没有把它放在 sniff 之后、domain 规则之前。若 TUN 的 `route_exclude_address_set` 因故未生效（如规则集未加载/缓存异常），国内 IP 会进 TUN 并只经过 sniff → domain → hijack-dns → final，没有在规则层被显式直连，可能落到 final（direct）或误匹配到 domain，出现国内仍走代理/微信慢。  
与 sing-box 对齐的做法：在 **route.rules 里、sniff 之后**增加一条 `{ "rule_set": "geoip-cn", "outbound": "direct" }`，与迁移文档一致，形成「TUN 排除 + 路由规则直连」双重保障。

---

## 5. 为何国内 IP 可能仍走代理、微信发图慢（排查思路）

- **download_detour**：`"proxy"` 表示用 proxy 出站下载规则集；`"direct"` 表示直连下载。在直连无法访问 raw.githubusercontent.com 的环境下必须用 `"proxy"`，改为 `"direct"` 会导致下载失败。
- **首次下载失败**：sing-box 核心在 `rule_set_remote.go` 中，首次 fetch 失败会 **return error**，导致 service Start 失败（VPN 连不上），**不会**静默「规则集为空继续跑」。因此若 VPN 能连上，规则集要么来自缓存要么首次下载已成功。
- 若仍出现国内走代理/微信慢，更可能的方向：① **route.rules 顺序**（是否有「国内直连」规则且顺序在代理规则之前）；② **route_exclude_address_set** 与 TUN 的配合是否按预期生效；③ **缓存**（cache.db）是否异常或与当前 config 不匹配；④ 你之前修好的「srs 加载顺序或某条规则」可能是 **rule_set 数组顺序** 或 **route.rules 里某条规则顺序**，而不是 download_detour。

---

## 6. 建议操作

### 6.1 确认 geoip-cn 是否被核心加载（必做）

1. **看扩展日志**  
   - 在扩展/系统日志中搜索：`updated rule-set geoip-cn` 或 `update rule-set geoip-cn: not modified`。  
   - 若有，说明规则集已下载或使用缓存并生效。  
2. **看缓存文件**  
   - 在 App Group 的 basePath（即 sharedDirectory）下看是否出现 **`cache.db`**（或核心使用的其它缓存文件名）。  
   - 有且 VPN 曾成功启动，可佐证规则集曾被写入。

若**从未**出现上述日志且**没有** cache，则说明远程 rule-set 未成功加载，此时 `route_exclude_address_set: ["geoip-cn"]` 不会起作用。

### 6.2 在 route.rules 中增加「rule_set geoip-cn ⇒ direct」（推荐）

与 sing-box 迁移文档一致，在 **route.rules** 里、**sniff 之后、domain 规则之前**增加一条：

```json
{
  "rule_set": "geoip-cn",
  "outbound": "direct"
}
```

这样即使 TUN 的 `route_exclude_address_set` 因故未生效，路由规则层仍会把命中 geoip-cn 的流量直连。需同时修改 **default_profile.json**（bundle 模板）和 **App Group 下已存在的 profile**（如 config_1.json），或重新从默认配置创建 profile 后生效。

### 6.3 与 sing-box 完全对齐路径（可选）

在 `vpn_extension_macos/PacketTunnelProvider.swift` 的 `prepareBaseDirectories` 里，把传给 LibboxSetup 的路径从 `.path` 改为 `.relativePath`，与 sing-box 一致：

```swift
return (
    baseDirURL: baseDirURL,
    basePath: baseDirURL.relativePath,
    workingPath: workingDirURL.relativePath,
    tempPath: cacheDirURL.relativePath
)
```

这样在「传参语义」上与 SFM 完全一致，便于以后对照 sing-box 行为。

---

## 7. 参考

- 我们：`openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift`（应用级）、`openmesh-apple/MeshFluxMac/default_profile.json`。  
- sing-box：`sing-box/clients/apple/Library/Network/ExtensionProvider.swift`、`Library/Shared/FilePath.swift`。  
- 验证与日志说明：`openmesh-apple/docs/REMOTE_RULE_SET_VERIFY.md`。
