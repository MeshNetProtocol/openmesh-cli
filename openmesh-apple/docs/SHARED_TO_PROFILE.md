# shared 目录与 Profile 的关系

**目标读者**：改造 MeshFluxMac 对齐 sing-box SFM 的 Profile 方案时，需要理解当前「shared 两文件」与「Profile」的对应关系，以及如何将 shared 规则转换成 sing-box 可用的 Profile 配置。

---

## 一、shared 目录下的两个文件

路径：`openmesh-apple/shared/`（源码中）；运行时由主 App 同步到 **App Group** 的 `MeshFlux/` 子目录，供应用级 extension 读取。

| 文件 | 作用 | 内容概要 |
|------|------|-----------|
| **routing_rules.json** | **命中 URL 的规则**：哪些域名/后缀走代理 | `version` + `domain` / `domain_suffix` / `ip_cidr` / `domain_regex` 等数组；extension 会将其转成 sing-box `route.rules` 中的 `domain_suffix` / `domain` 等规则，outbound 为 `proxy` |
| **singbox_base_config.json** | **连接服务器的配置**：完整 sing-box 模板 | 包含 `dns`、`inbounds`、`outbounds`（代理服务器如 shadowsocks）、`route`（基础骨架：rules 里仅有 sniff、hijack-dns 等），**不包含**由 routing_rules 生成的那批按域名命中的规则 |

也就是说：

- **routing_rules.json** = 规则数据（命中谁走代理）。
- **singbox_base_config.json** = 一份「可运行但规则未展开」的 sing-box 配置模板。

---

## 二、Profile（SFM 方案）是什么

在 sing-box/clients/apple 的 SFM 方案中：

- **Profile** = 一条数据库记录，指向**一个文件**（例如 `configs/config_1.json`）。
- 该文件内容 = **一整份完整的 sing-box 配置 JSON**（可直接交给 libbox 使用）。
- Extension 通过 `SharedPreferences.selectedProfileID` → `Profile` → `profile.read()` 得到这份**完整配置字符串**，不再在 extension 里拼装「base + 规则」。

因此：

- **一个 Profile ≈ 一个完整的 sing-box config 文件**（一对一）。
- 当前「shared 两文件」相当于：**把「完整 config」拆成了「服务器/基础配置」+「规则」两部分**；要对齐 SFM，就需要把这两部分**合并成一份**完整 config，再以「一个文件 + 一个 Profile」的形式使用。

---

## 三、shared 两文件与 Profile 的对应关系

- **routing_rules.json**：提供「命中 URL 的规则」数据 → 最终对应完整 config 里 `route.rules` 中「按 domain/domain_suffix 走 proxy」的那一段。
- **singbox_base_config.json**：提供「连接服务器的配置」→ 对应完整 config 的其余部分（dns、inbounds、outbounds、route 骨架等）。

合并规则（与当前应用级 extension 的 `buildConfigContent()` 一致）：

1. 以 **singbox_base_config.json**（或 App Group 中的 `singbox_config.json`）为**基础 config**。
2. 从 **routing_rules.json** 解析出 `DynamicRoutingRules`，再转成 sing-box 的 `route.rules` 片段（domain_suffix / domain 等，outbound 为 `proxy`）。
3. 将这段规则**按顺序**插入到 `route.rules` 中：**sniff** → **上述域名规则** → **hijack-dns**（并保留原有 `route.final` 等）。
4. 得到一份**完整的 sing-box config JSON 字符串**。

这份「完整 config 字符串」就是：

- **Extension 在「无 Profile」回退路径下**用 `buildConfigContent()` 得到的那份内容；
- 也是**我们「用 shared 生成默认 Profile」时**应写入 `configs/config_xxx.json` 的内容。

因此：

- **shared 两文件** → 经过上述**一次合并** → **一份完整 sing-box config** → 可存为一个 **config 文件** → 对应 **一个 Profile**。
- 转换关系：**routing_rules.json + singbox_base_config.json（或 singbox_config.json）→ 合并 → 一个 Profile 所指向的那一份完整 config 文件**。

---

## 四、如何将 shared 转换成 sing-box 可用的 Profile

1. **合并**  
   使用与 extension 相同的逻辑：  
   - 读入 base config（App Group 的 `singbox_config.json` 或 bundled `singbox_base_config.json`）。  
   - 读入 App Group 的 `routing_rules.json`，解析并转成 sing-box `route.rules` 片段。  
   - 按顺序拼好 `route.rules`（sniff → 域名规则 → hijack-dns），得到**完整 config 字符串**。

2. **落盘为 config 文件**  
   将上面得到的字符串写入 App Group 下的 `configs/config_default.json`（或 `config_<id>.json`）。

3. **创建 Profile 并选中**  
   - 在 DB 中插入一条 Profile：`name`（如「默认配置」）、`type: .local`、`path` = 上一步 config 文件的路径。  
   - 将 `SharedPreferences.selectedProfileID` 设为该 Profile 的 id。

之后 Extension 就会通过 `selectedProfileID` → `profile.read()` 拿到这份「由 shared 合并而来」的完整 config，与 SFM 的 Profile 方案一致；不再依赖「extension 内读两文件再 buildConfigContent」的旧路径。

---

## 五、应用级 extension 当前逻辑（对照）

- **vpn_extension_macos**（应用级）在 `resolveConfigContent()` 中：
  - 若有 `selectedProfileID` 且能取到对应 Profile：使用 `profile.read()` 得到完整 config（**Profile 路径**）。
  - 否则：回退到 `buildConfigContent()`（**shared 两文件路径**）：读 App Group 的 `singbox_config.json` + `routing_rules.json`，在内存中合并成完整 config。

因此：

- **Profile 方案**：一个文件 = 一个完整 config，extension 只做 `profile.read()`。
- **当前 shared 方案**：两个文件在 extension 里合并成一份完整 config。
- **转换**：在主 App 侧做「合并 + 写 config 文件 + 建 Profile」，之后 extension 就只走 Profile 路径，shared 两文件仅作为**默认数据源**或迁移来源。

---

## 六、小结

| 概念 | 含义 |
|------|------|
| **routing_rules.json** | 命中 URL 的规则数据（域名/后缀等），用于生成 `route.rules` 中走 proxy 的规则 |
| **singbox_base_config.json** | 连接服务器的配置模板（dns、inbounds、outbounds、route 骨架） |
| **Profile** | 一条记录 + 一个文件，文件内容 = **完整 sing-box config** |
| **default_profile.json** | 工程内**一份**合并后的默认配置（rules + 服务器配置），作为首次安装时的默认 Profile |

## 七、当前实现（应用级 MeshFluxMac + vpn_extension_macos）

- **工程内**：`MeshFluxMac/default_profile.json` 由 `shared/routing_rules.json` + `shared/singbox_base_config.json` 合并生成，加入 MeshFluxMac 与 vpn_extension_macos 的 Resources；**shared 目录及其两个配置文件不再被应用级 target 使用**。
- **首次启动**：若 profiles 表为空，主 App 从 bundle 读取 `default_profile.json`，写入 `configs/config_1.json`，创建 Profile「默认配置」并设为 selectedProfileID，之后按普通 Profile 安装/使用。
- **Extension**：优先 `selectedProfileID` → `profile.read()`；若无 Profile 则使用 bundle 中的 `default_profile.json`；再回退到旧的 buildConfigContent()（仅兼容旧环境）。
- **新建配置**：ProfilesView 的「新建配置」使用 bundle 中的 `default_profile.json` 作为模板。
