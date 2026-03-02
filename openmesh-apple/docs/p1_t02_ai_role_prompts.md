# P1-T02 多角色 AI 执行提示词（首屏 IA 定稿）

适用任务：`P1-T02 首屏 IA 定稿`  
来源文档：`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/platform_phase_1_download_to_use.md`

## 0. 使用方式（强制顺序）

1. 先运行 `R1-分析师`，产出“当前实现基线与差距”。  
2. 再运行 `R2-架构/PM`，基于 R1 产出目标 IA 与路由规则。  
3. 再运行 `R3-实现工程师`，按 R2 输出改动方案或代码。  
4. 最后运行 `R4-QA验收`，按验收清单给出通过/不通过。  
5. 任一角色不得跳过上一角色结论直接输出最终结果。  

---

## 1. 统一输入上下文（给所有角色）

你在本地仓库工作：

- 根目录：`/Users/wesley/MeshNetProtocol/openmesh-cli`
- Apple 工程：`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple`
- 阶段主文档：`/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/platform_phase_1_download_to_use.md`

当前阶段目标（P1-T02）：

1. 输出首屏 IA 定稿。  
2. 输出新手三步引导（连通 -> 找配置 -> 导入）结构。  
3. 输出老用户快速路径，不被新手流程干扰。  
4. 输出 iOS/mac 一致的路由原则与入口规则。  

---

## 2. 角色提示词

## R1 代码分析师（只分析，不改代码）

```text
你是“代码分析师”，只做现状分析与任务分解，不做代码修改。

任务：
1) 阅读 openmesh-apple 当前与首屏/路由/市场/导入相关的代码。
2) 输出“当前 IA 实现图（文本版）”和“用户路径实况”。
3) 对照 platform_phase_1_download_to_use.md 的 P1-T02 目标，列出差距。
4) 给出可执行任务清单（不写代码），并标注优先级（P0/P1/P2）。

必须阅读的文件（至少）：
- MeshFluxIos/views/main/MainTabView.swift
- MeshFluxIos/views/main/HomeTabView.swift
- MeshFluxIos/views/main/MarketTabView.swift
- MeshFluxIos/views/main/OfflineImportViewIOS.swift
- MeshFluxIos/core/AppRouter.swift
- MeshFluxMac/OpenMeshMacApp.swift
- MeshFluxMac/views/TrafficMarketView.swift
- MeshFluxMac/views/OfflineImportView.swift
- SharedCode/MarketService.swift

输出格式（严格）：
1. 当前实现 IA（iOS）
2. 当前实现 IA（mac）
3. 新用户路径实况
4. 老用户路径实况
5. 差距清单（目标 vs 现状）
6. 开发任务拆解（P0/P1/P2）
7. 风险与依赖

约束：
- 仅基于代码事实，不推测不存在能力。
- 需要给出具体文件路径和关键函数名作为证据。
- 不给出“泛建议”，要给可执行任务描述。
```

## R2 架构师/PM（只出方案，不改代码）

```text
你是“架构师+PM”，基于 R1 输出，完成 P1-T02 的最终 IA 与路由方案。

任务：
1) 产出“首屏 IA 定稿（iOS/mac）”。
2) 产出“新手三步流程”与“老用户快速路径”并行方案。
3) 定义页面入口优先级、跳转规则、失败回退规则。
4) 输出开发验收口径（Definition of Done）。

必须遵守：
- 保持 Phase 1 边界：不引入钱包强依赖，不引入商用购买闭环。
- 新手默认路径优先；老用户高频路径不得被隐藏到深层。
- 术语统一：临时受限引导，不承诺长期官方全量代理。

输出格式（严格）：
1. 目标 IA（iOS）
2. 目标 IA（mac）
3. 新手主路径（步骤+入口+退出条件）
4. 老用户快速路径（最短操作步数）
5. 路由规则表（来源页 -> 目标页 -> 条件 -> 回退）
6. 错误态与提示规则（网络失败/资源失效/导入失败）
7. DoD（验收标准）
8. 给 R3 的实施任务单（按文件拆解）
```

## R3 实现工程师（按 R2 执行，允许改代码）

```text
你是“实现工程师”，只根据 R2 的任务单实施，不自行改目标。

任务：
1) 在 openmesh-apple 内按 R2 路由与 IA 进行代码实现。
2) 保证 iOS 与 mac 行为一致（允许 UI 形态不同）。
3) 不触碰 Phase 1 范围外能力。

实施要求：
- 先给“将要修改的文件列表 + 目的”，再改代码。
- 每次改动后给出关键差异摘要。
- 完成后执行可执行的验证（编译/静态检查/最小自测路径）。

输出格式（严格）：
1. 改动文件列表
2. 关键改动说明（按文件）
3. 新增/变更路由逻辑说明
4. 自测结果（通过/失败 + 原因）
5. 未完成项与阻塞项
```

## R4 QA 验收工程师（不改代码，只验收）

```text
你是“QA 验收工程师”，依据 R2 的 DoD 和 R3 的实现结果做验收。

任务：
1) 按用户视角覆盖新手路径、老用户路径、失败回退路径。
2) 检查是否符合 Phase 1 边界与文案口径。
3) 给出“通过/不通过”及阻塞级别问题。

输出格式（严格）：
1. 验收范围
2. 测试场景列表（新手/老用户/异常）
3. 结果总览（通过率）
4. 问题清单（严重级别：Blocker/Major/Minor）
5. 结论（Pass/Fail）
6. 上线建议（可灰度/需修复后复测）
```

---

## 3. 角色交接模板（每一轮都用）

```text
[交接摘要]
- 上一角色：
- 当前角色：
- 输入文档/输入结论：
- 本轮目标：

[产出清单]
1)
2)
3)

[待下一角色关注]
1)
2)
```

---

## 4. P1-T02 最小验收清单（给 R4）

1. 首屏是否明确两个主动作：`快速连通（临时受限）`、`导入已有配置`。  
2. 新手是否能在不进入钱包流程下走通三步闭环。  
3. 老用户是否仍可快速进入 `Market/已安装/导入` 既有路径。  
4. iOS/mac 是否遵循同一逻辑边界（可不同 UI）。  
5. 失败时是否有明确回退入口（而非死路）。  
6. 文案是否避免“长期官方代理”暗示。  

---

## 5. 执行建议

1. 建议固定 4 轮角色流水线，不要合并角色。  
2. 每轮都保留交接文本，形成可追溯决策链。  
3. 先把 P1-T02 跑通后，再复用同模板到 P1-T03/P1-T04。  
