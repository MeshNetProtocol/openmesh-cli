# 配置文件完整性重构计划

> **总架构师指令文档**
> 本文档记录了针对 `openmesh-android` 工程的配置文件操作合规性审查结果，以及对应的修改计划、AI 执行提示词和验收标准。

---

## 一、核心原则

> **不修改配置文件的本来设定，不增加和删除配置文件的内容。**

这意味着：
- 配置文件从外部（Provider）加载后，其内容必须原样保存和使用
- 代码层面不允许向配置文件中注入、追加、删除或覆写任何字段
- 如果某平台有特殊需求（如 Android 特定的 tun 参数），应通过修改配置文件本身来满足，而不是通过代码运行时动态改写
- 保存到磁盘的配置，必须与加载进来的配置内容完全一致

---

## 二、审查结论总览

**总体结论：❌ 存在严重违规**

Android 工程在运行时（Runtime）存在大量的配置动态改写行为。虽然存储层（`InstallWizardDialog` 和 `ProviderStorageManager`）目前倾向于保留原始配置，但 VPN 启动的核心流程（`OpenMeshBoxService`）通过专门的"Sanitizer"和"Injector"类，对配置进行了深度的内容注入、规则重排和字段补全。

这完全违背了核心原则，形成了一种"用 Android 代码弥补配置缺陷"的反模式。

### 各文件审查结论

| 文件 | 结论 | 违规类型 |
| :--- | :---: | :--- |
| `OpenMeshConfigSanitizer.kt` | ❌ 严重违规 | 内容注入、结构修改、规则重排、字段删除 |
| `OpenMeshRoutingRuleInjector.kt` | ❌ 违规 | 内容注入（增加路由规则） |
| `OpenMeshTunConfigResolver.kt` | ❌ 违规 | 硬编码 fallback 地址，发明不存在的内容 |
| `OpenMeshBoxService.kt` | ❌ 违规（编排者） | 串联所有违规组件 |
| `ProviderStorageManager.kt` | ✅ 基本合规 | 存储层保留了原始配置 |
| `ProfileRepository.kt` | ✅ 基本合规 | 优先读取 config_full.json 原始快照 |

### 与 iOS 对比结论

| 特性 | Android 实现 | iOS 实现 | 结论 |
| :--- | :--- | :--- | :--- |
| 配置传递 | 读取 → **代码修改 (Sanitize/Inject)** → 传递 | 读取 → **直接传递 Data** | Android 违规 |
| 默认值处理 | 在 Kotlin 代码中补全 (MTU 等) | 未见代码补全逻辑 | Android 违规 |
| 存储结构 | 区分 `config.json` 和 `config_full.json` | 通常直接操作原文件 | Android 结构复杂化 |

---

## 三、修改计划

共分 **4 个任务（Task）**，按依赖顺序执行。

```
Task 1 (TunConfigResolver fallback 移除)  ─┐
                                             ├──> 均可独立并行执行
Task 2 (ConfigSanitizer 注入移除)         ─┤
                                             │
Task 3 (RoutingRuleInjector 对齐)        ──┘

              ↓ Task 2 & 3 完成后

Task 4 (BoxService 管道清理)  ──> 最终集成验证
```

---

## Task 1 — 移除 `OpenMeshTunConfigResolver.kt` 中的硬编码 Fallback 地址

**优先级：最高 | 风险：低 | 影响范围：1 个文件**

### AI 执行提示词

```
你是一名 Android Kotlin 工程师，正在修改文件：
D:\worker\openmesh-cli\openmesh-android\app\src\main\java\com\meshnetprotocol\android\vpn\OpenMeshTunConfigResolver.kt

【核心原则】不允许代码"发明"配置文件中不存在的内容。
如果配置文件中没有 tun address 字段，这是配置文件本身的问题，
不应由代码提供 fallback 地址来掩盖这个问题。

【当前违规代码 - 位于 resolve() 函数中，约第 20-28 行】：
    val addresses = parseCidrs(tunInbound.optJSONArray("address"))
    val fallbackAddresses = if (addresses.isEmpty()) {
        listOf(
            OpenMeshIpCidr("172.19.0.1", 30),
            OpenMeshIpCidr("fdfe:dcba:9876::1", 126),
        )
    } else {
        addresses
    }

【你需要做的修改】：
1. 删除 fallbackAddresses 的定义和整个 if/else 分支。
2. 将后续所有使用 fallbackAddresses 的地方，改为直接使用 addresses。
3. 在 addresses 为空时，不再"自造"地址，而是抛出清晰的异常：
   如果 addresses.isEmpty() 则 throw IllegalStateException(
       "Invalid profile: tun inbound missing 'address' field. " +
       "Please update the provider configuration."
   )
4. 不要修改文件中其他任何逻辑，只处理上述 fallback 相关代码。

【不允许做的事】：
- 不要修改 parseCidrs() 函数
- 不要修改 pickDnsServer() 函数
- 不要引入任何新的默认值或备选值

修改完成后，输出修改后的完整文件内容。
```

### 验收标准

1. 文件中不存在字符串 `"172.19.0.1"` 和 `"fdfe:dcba:9876"`
2. 文件中不存在 `fallbackAddresses` 变量名
3. 当配置缺少 `address` 字段时，`resolve()` 抛出 `IllegalStateException` 而非返回默认 IP
4. 代码可以正常编译，无语法错误
5. 文件中 `parseCidrs`、`pickDnsServer` 等函数体与修改前完全一致

---

## Task 2 — 重构 `OpenMeshConfigSanitizer.kt`，移除所有内容注入和结构改写

**优先级：高 | 风险：中 | 影响范围：1 个文件 + `OpenMeshBoxService.kt`**

### AI 执行提示词

```
你是一名 Android Kotlin 工程师，正在重构文件：
D:\worker\openmesh-cli\openmesh-android\app\src\main\java\com\meshnetprotocol\android\vpn\OpenMeshConfigSanitizer.kt

【核心原则】这个文件的所有操作都是在运行时改写 Provider 下发的原始配置，
这违反了"不修改配置文件的本来设定，不增加和删除配置文件的内容"的原则。
任何配置缺失或不规范，都应视为 Provider 配置问题，由报错反馈给上层，
而不是由代码静默修复。

【需要删除的违规函数和行为】：

1. 删除 ensureInboundTun() 私有函数（整个函数体）。
   违规原因：向配置中注入 mtu=1400、sniff=true、sniff_override_destination=true，
   这些字段本应在 Provider 配置文件中定义。

2. 删除 reorderAndInjectRouteRules() 私有函数（整个函数体）。
   违规原因：强制改变 route.rules 的顺序，并在缺失 sniff rule 时自动注入一条。
   配置文件里的规则顺序是 Provider 有意为之的，不应被代码改变。

3. 删除 injectFakeNodeForSingleNodeGroups() 私有函数（整个函数体）。
   违规原因：当 selector/urltest 组只有 1 个成员时，自动追加 "direct" 节点。
   这掩盖了配置问题，违反了"不增加内容"原则。

4. 修改 forceDebugOptions() 函数：
   删除 log.put("timestamp", true) 这一行（这是在往配置里写入新字段）。
   保留函数体中仅读取 currentLevel 并打 Log 的部分（纯读取无副作用）。
   如果函数体只剩下读 log level 的 log 语句，可以保留该函数作为纯日志观察函数，
   但函数名可以改为 logDebugOptions()，体现其非修改性质。

5. 修改 sanitize() 公开函数：
   删除对 ensureInboundTun(root) 的调用
   删除对 reorderAndInjectRouteRules(root) 的调用
   删除对 injectFakeNodeForSingleNodeGroups(root) 的调用
   保留对 forceDebugOptions(root) 的调用（改为 logDebugOptions(root) 如果你改名了）
   由于 sanitize() 现在不再修改任何内容，
   将函数重命名为 validateAndLog(configContent: String)，
   函数体直接返回原始 configContent，不再调用 root.toString()。

【必须保留的函数】：
- adaptTunAddressFamilies() 及其内部的 filterIpCidrs() 函数，
  这两个函数保持不变（IPv6 适配是 Android 平台层面的合理需求，另行评估）。

【你需要同时修改】：
OpenMeshBoxService.kt 文件中 prepareRuntimeConfig() 函数里：
  将 OpenMeshConfigSanitizer.sanitize(mergedConfig)
  改为 OpenMeshConfigSanitizer.validateAndLog(mergedConfig)
  （或者如果你没有改名，就删除 .sanitize() 调用，直接使用 mergedConfig）

修改完成后，分别输出两个文件的完整修改后内容。
```

### 违规详情参考

| 违规函数 | 违规行为 | 违规类型 |
| :--- | :--- | :--- |
| `ensureInboundTun()` | 注入 `mtu=1400`、`sniff=true`、`sniff_override_destination=true` | 内容注入（增加） |
| `reorderAndInjectRouteRules()` | 强制改变 `route.rules` 顺序，缺失时自动注入 sniff rule | 结构修改 + 内容注入 |
| `injectFakeNodeForSingleNodeGroups()` | 单成员组自动追加 `"direct"` 节点 | 内容注入（增加） |
| `forceDebugOptions()` | `log.put("timestamp", true)` 写入配置字段 | 内容注入（增加） |
| `adaptTunAddressFamilies()` | 根据网络状态删除 IPv6 地址 | **保留**（平台适配，另行评估） |

### 验收标准

1. `OpenMeshConfigSanitizer.kt` 中不存在以下函数：`ensureInboundTun`、`reorderAndInjectRouteRules`、`injectFakeNodeForSingleNodeGroups`
2. 文件中不存在对 `inbound.put("mtu",`、`inbound.put("sniff",`、`route.put("rules",` 的调用
3. `sanitize()` 函数（或重命名后的函数）的返回值与传入的 `configContent` 完全相同（不做任何 JSON 改写）
4. `adaptTunAddressFamilies()` 函数与修改前逻辑完全一致
5. `OpenMeshBoxService.kt` 编译后无报错，VPN 启动流程调用链不出现对已删除函数的引用

---

## Task 3 — 审查并清理 `OpenMeshRoutingRuleInjector.kt` 与 iOS 对齐

**优先级：中 | 风险：中 | 影响范围：1 个文件 + iOS 对比分析**

### AI 执行提示词

```
你是一名跨平台（Android/iOS）工程师，负责审查以下两个文件并给出修改建议：

Android 文件：
D:\worker\openmesh-cli\openmesh-android\app\src\main\java\com\meshnetprotocol\android\vpn\OpenMeshRoutingRuleInjector.kt

iOS 参考目录：
D:\worker\openmesh-cli\openmesh-apple\MeshFluxIos\core\

【背景】
Android 工程中存在 routing_rules.json 文件，它与主配置 config_full.json 分开存储。
在 VPN 启动时，OpenMeshRoutingRuleInjector 负责把 routing_rules.json 的规则
注入到主配置的 route.rules 数组中，再传给 Go 引擎。

【你的任务】：

Step 1：阅读 iOS 的 core/ 目录下所有 Swift 文件，寻找以下证据：
  a. iOS 是否也存在 routing_rules.json（或同名/同功能的文件）？
  b. iOS 是否有对应的"合并 routing_rules 到主配置"的逻辑？
  c. 如果有，iOS 是如何实现的（是在代码层做 JSON 合并，还是传给引擎前做预处理）？

Step 2：基于 Step 1 的结论，判断：
  情况A：iOS 有相同的合并逻辑
    → Android 的 RoutingRuleInjector 是跨平台一致的实现，架构上可以保留。
      但需要确保：注入逻辑不要额外修改 sniff rule 的位置或其他字段（ensureSniffRule()
      函数内部有向 routeRules 插入新 sniff rule 的逻辑，如果 Sanitizer 已经在 Task 2
      中保证 sniff rule 被删除，这里应该也不再需要），请评估并给出结论。

  情况B：iOS 没有相同的合并逻辑，或合并方式完全不同
    → 说明 Android 的 routing_rules.json 设计与 iOS 存在架构差异，
      请描述差异，并建议是否应该统一成由 Go 引擎层合并，
      或者由配置下发时服务端合并，以彻底消除 Kotlin 层的 JSON 操作。

Step 3：无论情况A还是B，检查 ensureSniffRule() 函数：
  由于 Task 2 已经删除了 OpenMeshConfigSanitizer 中对 sniff rule 的注入逻辑，
  这里 ensureSniffRule() 是否还有必要存在？
  如果 Task 2 的修改已经保证了 route.rules 数组的结构来自原始配置，
  则 RoutingRuleInjector 在注入时应该只在 sniff rule 之后插入内容，
  而不应该自己注入 sniff rule。
  请修改 inject() 函数：
    - 如果 routeRules 中找不到 sniff rule，不要注入，
      而是在 sniff rule 缺失时直接在数组头部之后（index=0）插入路由规则，
      并打印一条 Warning 日志说明配置中缺少 sniff rule。
    - 删除 ensureSniffRule() 函数。

修改完成后，输出修改后的 OpenMeshRoutingRuleInjector.kt 完整内容，
并附上 Step 1 和 Step 2 的分析结论报告。
```

### 违规详情参考

`ensureSniffRule()` 函数会在 `route.rules` 中找不到 sniff rule 时，自动向数组头部插入 `{"action": "sniff"}` 这条规则，属于"内容注入"违规。

### 验收标准

1. `OpenMeshRoutingRuleInjector.kt` 中不存在 `ensureSniffRule()` 函数
2. `inject()` 函数不再向 `routeRules` 数组中插入 `{"action": "sniff"}` 这条规则
3. 附带一份 iOS vs Android 的 routing_rules 合并逻辑对比报告
4. 文件可正常编译，`inject()` 函数签名保持不变

---

## Task 4 — 清理 `OpenMeshBoxService.kt` 的配置预处理管道，并添加配置完整性验证

**优先级：高 | 风险：中 | 影响范围：1 个文件**

> ⚠️ **前置依赖：此 Task 必须在 Task 2 和 Task 3 完成后执行。**

### AI 执行提示词

```
你是一名 Android Kotlin 工程师，正在清理以下文件：
D:\worker\openmesh-cli\openmesh-android\app\src\main\java\com\meshnetprotocol\android\vpn\OpenMeshBoxService.kt

【前提】Task 2 和 Task 3 已经完成，意味着：
- OpenMeshConfigSanitizer.sanitize() 已被重命名/重构为 validateAndLog()，不再修改配置内容
- OpenMeshRoutingRuleInjector.inject() 不再注入 sniff rule

【你的任务】：

Step 1：重构 prepareRuntimeConfig() 函数。
  当前的函数流程是：rawConfig -> inject routing rules -> sanitize -> adaptIPv6 -> finalConfig
  目标流程应改为：rawConfig -> merge routing rules (if any) -> adaptIPv6 -> finalConfig

  具体改动：
  a. 保留 loadRoutingRules(profile) 的调用（加载独立的 routing_rules.json 文件）
  b. 保留 OpenMeshRoutingRuleInjector.inject() 的调用（合并路由规则）
  c. 将 OpenMeshConfigSanitizer.sanitize() 调用改为 validateAndLog()（或直接删除，
     取决于 Task 2 的重命名结果；无论如何，不应该有任何修改配置内容的调用）
  d. 保留 OpenMeshConfigSanitizer.adaptTunAddressFamilies() 的调用（IPv6 适配保留）
  e. 在函数中添加一段配置完整性检查日志：在传给引擎前，读取并打印以下信息：
     - inbounds 中是否有 type=tun 的条目（true/false）
     - tun inbound 是否包含 mtu 字段（true/false）
     - tun inbound 是否包含 sniff 字段（true/false）
     - route.rules 的总数量
     - route.rules 中第一条的 action 是否为 "sniff"（true/false）
     这些日志帮助我们在 LogCat 中快速验证配置完整性，而无需改写配置。

Step 2：在 writeRuntimeDiagnostics() 中，将诊断报告中对 "effective" config 的描述
  更新为 "runtime_adjusted_config"（因为只有 IPv6 适配，没有内容修改，
  更名更准确地反映其含义）。

Step 3：不要修改 startWithProfile()、reload()、stop() 等函数的任何业务逻辑。

修改完成后，输出完整的修改后文件内容。
```

### 配置预处理管道对比

**修改前（违规）：**
```
rawConfig
  └─> OpenMeshRoutingRuleInjector.inject()    ← 注入路由规则
      └─> OpenMeshConfigSanitizer.sanitize()  ← 改写 MTU/Sniff/规则顺序/节点
          └─> adaptTunAddressFamilies()        ← 删除 IPv6 地址
              └─> Go 引擎
```

**修改后（合规）：**
```
rawConfig
  └─> OpenMeshRoutingRuleInjector.inject()    ← 合并 routing_rules.json（保留）
      └─> validateAndLog()                     ← 纯日志，不改写内容
          └─> adaptTunAddressFamilies()        ← IPv6 适配（保留）
              └─> Go 引擎
```

### 验收标准

1. `prepareRuntimeConfig()` 的调用链中不存在任何会修改配置 JSON 结构的操作
2. `OpenMeshConfigSanitizer` 的任何被删除的函数都不再被 `BoxService` 调用
3. LogCat 在 VPN 启动时能打印出 `tun has_mtu=true/false, has_sniff=true/false` 格式的日志
4. `adaptTunAddressFamilies()` 调用保留，IPv6 适配功能不受影响
5. 工程整体可正常编译，VPN 启动流程无编译期错误

---

## 四、最终验证检查清单

所有 Task 完成后，执行以下 grep 命令确认所有违规已消除。**如果搜索到结果，说明修改不彻底。**

```bash
# 在工程根目录执行（Windows 用 findstr 或 PowerShell Select-String）

# 1. 不应存在：MTU 注入
grep -r "inbound.put(\"mtu\"" .

# 2. 不应存在：sniff 字段注入
grep -r "inbound.put(\"sniff\"" .

# 3. 不应存在：route rules 整体替换
grep -r "route.put(\"rules\"" .

# 4. 不应存在：fake direct 节点注入
grep -r "members.put(\"direct\"" .

# 5. 不应存在：硬编码 fallback IPv4
grep -r "172.19.0.1" .

# 6. 不应存在：硬编码 fallback IPv6
grep -r "fdfe:dcba" .

# 7. 不应存在：sniff rule 自动注入函数
grep -r "ensureSniffRule" .

# 8. 不应存在：fake 节点注入函数
grep -r "injectFakeNode" .

# 9. 不应存在：规则重排函数
grep -r "reorderAndInject" .

# 10. 不应存在：tun 字段补全函数
grep -r "ensureInboundTun" .
```

**PowerShell 等效命令（Windows）：**
```powershell
$patterns = @("inbound.put\(`"mtu`"", "inbound.put\(`"sniff`"", "route.put\(`"rules`"",
              "members.put\(`"direct`"", "172.19.0.1", "fdfe:dcba",
              "ensureSniffRule", "injectFakeNode", "reorderAndInject", "ensureInboundTun")
foreach ($p in $patterns) {
    $results = Get-ChildItem -Recurse -Filter *.kt | Select-String -Pattern $p
    if ($results) { Write-Host "❌ FOUND: $p"; $results } else { Write-Host "✅ CLEAN: $p" }
}
```

---

## 五、附录：违规文件原始行为摘要

### `OpenMeshConfigSanitizer.kt` 违规行为清单

```
【违规1】ensureInboundTun() ~第55行
  行为：若 mtu <= 0，注入 mtu=1400
  行为：若缺少 sniff，注入 sniff=true
  行为：若缺少 sniff_override_destination，注入 sniff_override_destination=true
  类型：内容注入（增加）
  持久化：否（运行时内存操作）

【违规2】reorderAndInjectRouteRules() ~第76行
  行为：将 route.rules 按 sniff -> hijack-dns -> others 顺序重排
  行为：缺少 sniff rule 时自动创建并插入
  类型：结构修改 + 内容注入
  持久化：否（运行时内存操作）

【违规3】injectFakeNodeForSingleNodeGroups() ~第134行
  行为：selector/urltest 组成员为1时，追加 "direct" 字符串
  类型：内容注入（增加）
  持久化：否（运行时内存操作）

【违规4】forceDebugOptions() 中的 log.put("timestamp", true)
  行为：向 log 对象写入 timestamp=true 字段
  类型：内容注入（增加）
  持久化：否（运行时内存操作）
```

### `OpenMeshTunConfigResolver.kt` 违规行为清单

```
【违规】resolve() ~第20-28行
  行为：address 字段为空时，自造 172.19.0.1/30 和 fdfe:dcba:9876::1/126
  类型：内容发明（凭空创造不存在的配置）
  持久化：否（运行时内存操作）
```

### `OpenMeshRoutingRuleInjector.kt` 违规行为清单

```
【违规】ensureSniffRule() ~第67-80行
  行为：route.rules 中找不到 sniff rule 时，自动在头部插入 {"action":"sniff"}
  类型：内容注入（增加）
  持久化：否（运行时内存操作）
```

---

*文档生成时间：由总架构师在配置合规性审查后生成*
*关联工程：`D:\worker\openmesh-cli\openmesh-android`*
*参考基准：`D:\worker\openmesh-cli\openmesh-apple\MeshFluxIos`*
