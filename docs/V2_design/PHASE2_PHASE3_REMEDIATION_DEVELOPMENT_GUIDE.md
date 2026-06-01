# Phase 2 / Phase 3 评审问题修复开发指南

**文档日期**: 2026-04-24  
**适用范围**: `market-blockchain` Phase 2 / Phase 3 评审问题修复实施  
**目标读者**: 负责实际修复代码的 AI / 工程师  
**文档定位**: 本文档是当前修复工作的**开发执行主文档**，用于指导后续 AI 按统一顺序、统一边界、统一验收标准实施修复。

---

## 1. 文档来源与事实依据

本指南基于以下评审与计划文档整理而成：

### 最新评审输入
- `docs/V2_design/DESIGN_QUALITY_REVIEW_2026-04-24.md`
- `docs/V2_design/code_review_ai1_功能实现与业务正确性评审_补充-订阅生命周期与状态流转.md`

### 相关未提交文档
- `docs/V2_design/code_review_ai1_功能实现与业务正确性评审.md`
- `docs/V2_design/PHASE2_PHASE3_FIX_PLAN.md`
- `docs/V2_design/CODE_REVIEW_TASK.md`
- `docs/V2_design/AI_TASK_ASSIGNMENT.md`
- `docs/V2_design/AI_REVIEW_PROMPT_1.md`
- `docs/V2_design/AI_REVIEW_PROMPT_2.md`

### 单一事实源约定
在当前修复阶段，关于项目真实状态，以本文档和 `docs/V2_design/PHASE2_PHASE3_FIX_PLAN.md` 为准。  
任何“Phase 2 / Phase 3 已完成”“ready for Phase 4”之类说法，在相关问题修复并验证前，**一律视为不成立**。

---

## 2. 当前真实状态判断

基于上述评审，当前项目不是“差少量收尾”，而是：

> **核心结构已存在，但订阅生命周期、Xray 同步、流量持久化、后台展示、事务一致性、安全边界和测试保护都没有形成可靠闭环。**

### 当前已经存在的内容
- 数据表基础结构与部分 migration 已存在
- Subscription / Authorization / Charge / Event 基础模型存在
- 部分 repository / service / handler 骨架已存在
- Xray gRPC 连接骨架已存在
- admin 页面静态界面已存在
- 部分文档、测试骨架已存在

### 当前没有形成闭环的关键能力
1. 创建订阅后数据未可靠落库
2. 首次扣费成功后激活链路不可靠
3. 订阅状态变化未可靠驱动 Xray Add/Remove 用户
4. Xray client 核心方法未实现
5. 流量采集无法稳定映射到真实订阅
6. admin subscriptions API 未真正接通或缺少完整保护
7. 多表更新无事务边界
8. shutdown / scheduler 生命周期设计不稳
9. admin 认证边界高度可疑
10. 测试与文档显著高估完成度

---

## 3. 修复总目标

本轮修复不是继续扩功能，而是把 Phase 2 / Phase 3 修到**最小可信状态**。

### 本轮完成后必须满足
1. 创建订阅返回成功时，相关数据已真实写入数据库
2. 首次激活、取消、过期、续费这些关键状态变化有一致的业务入口
3. 关键状态变化能正确驱动 Xray 用户同步，或明确进入待同步失败状态
4. Xray 流量采集可以正确更新到目标订阅
5. admin 页面能真实读取订阅与流量数据
6. 多表关键更新具备事务一致性
7. 应用 shutdown 重复调用不 panic
8. admin 接口具备明确认证边界，至少不能处于“是否裸露未知”的状态
9. 核心链路至少具备最低限度自动化测试
10. 文档只描述已被代码和测试验证过的事实

### 本轮明确不做
以下内容不属于本轮目标，除非修复主链路时必然涉及：
- 多 Xray 服务器管理
- 流量配额/限速完整策略
- Phase 4 客户端适配
- 端到端部署体系优化
- UI 美化或后台增强功能
- 为未来扩展做额外抽象

---

## 4. 开发原则

### 4.1 先闭环，再优化
必须优先修复能影响业务真实性的问题：
- 返回成功但未落库
- 状态变了但权限没同步
- 流量看起来在采集但没入库
- 页面看起来有数据但接口未接通

### 4.2 统一状态迁移入口
`pending -> active -> cancelled / expired -> renewed / changed plan` 不应分散在多个 service 各自硬改字段。  
应收敛成少量明确的状态迁移入口，并统一定义：
- DB 更新内容
- event 写入内容
- Xray 同步动作
- 失败处理策略

### 4.3 DB 事务与外部副作用分离
数据库内多表更新必须纳入单事务。  
Xray / 链上调用这类外部副作用，不应直接混进裸串行 DB 写入流程。

### 4.4 文档不能领先代码
任何修复完成后，只有在**代码已改 + 测试已覆盖 + 路径已验证**后，才能把文档状态更新为“完成”。

### 4.5 不做无关重构
除非某个设计问题直接阻断当前修复，否则不要顺手重构无关模块。

---

## 5. 建议实施顺序

建议按 4 个阶段推进，每阶段都要可验证。

### 阶段 A：先修主业务闭环
1. 创建订阅落库
2. 首次激活链路修正
3. 统一订阅状态迁移入口
4. Xray 技术路线定稿
5. Xray client 核心方法实现
6. Xray 同步接入状态迁移
7. 流量采集映射修正
8. admin subscriptions API 接通

### 阶段 B：修一致性与生命周期稳定性
1. 创建 / 首次扣费 / 续费 / 升级链路事务化
2. scheduler Stop 幂等化
3. repository context 设计统一
4. 事件写入错误处理补齐
5. 1000 条同步上限修复

### 阶段 C：修安全边界与 handler 语义
1. admin API / admin UI 认证边界明确
2. upgrade / downgrade / create 等 handler 错误码语义修正
3. 输入校验与地址规范化补齐
4. admin handler 吞错问题修复

### 阶段 D：补测试与修正文档
1. 主链路测试
2. 失败路径测试
3. shutdown / scheduler 测试
4. admin 权限与错误返回测试
5. 项目文档统一降级或更新为真实状态

---

## 6. 工作包拆分

以下工作包可直接作为 AI 修复任务输入。每个工作包都要满足“修改范围、实现要求、验收标准”。

---

## WP-1 创建订阅链路真实落库

### 问题来源
- `code_review_ai1_功能实现与业务正确性评审.md`
- `DESIGN_QUALITY_REVIEW_2026-04-24.md`

### 目标文件
- `market-blockchain/internal/service/subscription_service.go`
- 相关 authorization / charge / event repository / service 文件

### 要解决的问题
当前 `CreateSubscription()` 只组装对象，不保证真实持久化，API 语义失真。

### 实现要求
- `CreateSubscription()` 成功返回前，必须已完成：
  - subscription 持久化
  - authorization 持久化
  - charge 持久化
  - 初始 event 写入
- 明确初始状态是否为 `pending`
- 返回对象必须与数据库真实状态一致
- 不允许再出现“返回 201 但 DB 查不到”的情况

### 验收标准
- 创建接口调用成功后，DB 可查询到完整记录
- 后续按 ID 查询可以读到该订阅
- 任何中间失败都不会留下半成品数据

---

## WP-2 修复首次激活链路

### 问题来源
- `code_review_ai1_功能实现与业务正确性评审_补充-订阅生命周期与状态流转.md`

### 目标文件
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/repository/authorization_repository.go`
- `market-blockchain/internal/repository/charge_repository.go`
- 对应 postgres 实现文件

### 要解决的问题
`ExecuteFirstCharge()` 当前通过空字符串查询 authorization / charge，业务上不可用。

### 实现要求
- 提供按主键 / 真实唯一键查询的 repository 方法
- 不允许再使用空字符串查询后再做 ID 比较
- 明确首次扣费成功后：
  - charge 状态如何更新
  - authorization 如何更新
  - subscription 如何从 `pending` 进入 `active`
  - event 如何记录
- 与 Xray 同步逻辑打通（见 WP-5）

### 验收标准
- 首次扣费成功时，`pending -> active` 可靠成立
- charge / authorization / subscription 三者状态一致
- 查询路径具备明确业务语义

---

## WP-3 统一订阅生命周期状态机入口

### 问题来源
- 生命周期补充评审文档
- Phase 2 / Phase 3 fix plan

### 目标文件
- `market-blockchain/internal/domain/subscription.go`
- `market-blockchain/internal/service/subscription_service.go`
- `market-blockchain/internal/service/subscription_management_service.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/renewal_service.go`
- `market-blockchain/internal/service/subscription_upgrade_service.go`

### 要解决的问题
状态修改分散在多个 service，导致副作用不一致。

### 实现要求
至少统一以下状态迁移：
- 创建订阅：进入 `pending`
- 首次支付成功：`pending -> active`
- 用户取消：`active -> cancelled`
- 续费失败 / allowance 不足：`active -> expired`
- 续费成功：active 周期延长
- 升级 / 降级：明确是否即时生效或延期生效

每个迁移都必须定义：
- 修改哪些表
- 写哪些事件
- 是否同步 Xray
- 失败时如何处理

### 验收标准
- 代码中不再出现多个 service 各自偷偷改 `subscription.Status`
- 生命周期关键路径具备统一业务语义

---

## WP-4 统一 Xray 技术路线并实现 client 核心方法

### 问题来源
- 两份 AI-1 评审
- 设计质量评审
- 现有 fix plan

### 目标文件
- `market-blockchain/internal/xray/client.go`
- `market-blockchain/internal/config/config.go`
- `market-blockchain/docs/XRAY_SETUP.md`
- `docs/V2_design/implementation/phase3_traffic_integration_complete.md`

### 要解决的问题
文档写 CLI wrapper，代码是 gRPC stub，四个核心方法未实现。

### 技术决策建议
基于现有代码骨架，继续走 **gRPC 路线**，不要再切回 CLI wrapper。

### 必须实现的方法
- `AddUser`
- `RemoveUser`
- `QueryUserTraffic`
- `QueryAllUsersTraffic`

### 需要处理的路径
- Xray 不可达
- 用户不存在
- 重复添加
- 空结果
- 超时
- inboundTag 生效

### 验收标准
- 四个方法不再返回 `not implemented yet`
- 文档、配置、代码统一描述 gRPC 方案
- `XRAY_INBOUND_TAG` 真实参与用户管理动作

---

## WP-5 把 Xray 同步接入订阅状态变化

### 问题来源
- AI-1 主评审
- 生命周期补充评审
- 设计质量评审

### 目标文件
- `market-blockchain/internal/service/xray_sync_service.go`
- `market-blockchain/internal/app/app.go`
- `market-blockchain/internal/service/subscription_management_service.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/renewal_service.go`

### 要解决的问题
激活 / 取消 / 过期等状态变化没有形成真实 Xray 同步闭环。

### 实现要求
至少接通以下场景：
- 首次激活成功 -> `AddUser`
- 取消订阅 -> `RemoveUser`
- 订阅过期 -> `RemoveUser`
- 全量对账 -> `SyncAllActiveSubscriptions`

### 设计要求
- 明确同步失败策略：
  - 直接返回错误
  - 标记待重试
  - 后台补偿
  - 禁止静默忽略
- app 初始化时，只有在 Xray 能力可用时才启动相关后台任务，或明确 degraded mode 语义

### 验收标准
- 状态变化与访问权限同步不再脱节
- 不再出现 DB 显示 active，但 Xray 没有用户的静默断链

---

## WP-6 修复流量采集与 subscription 映射

### 问题来源
- AI-1 主评审
- AI-2 设计评审

### 目标文件
- `market-blockchain/internal/service/traffic_stats_service.go`
- `market-blockchain/internal/repository/subscription_repository.go`
- `market-blockchain/internal/store/postgres/subscription_repository.go`

### 要解决的问题
`GetByIdentityAndPlan(email, "")` 的用法与 repository 契约冲突，导致流量基本无法入库。

### 实现要求
- 禁止继续使用空 `planID` 偷渡业务语义
- 新增或重构明确查询接口，例如：
  - `GetActiveByIdentity(...)`
  - 或更稳定的 `GetByXrayUserKey(...)`
- 如果一个身份可存在多个订阅，必须明确定义 Xray user 与 subscription 的唯一映射规则
- 更新 `uplink / downlink / total_traffic`

### 验收标准
- 流量采集成功后，数据库中对应 subscription 的流量字段正确更新
- 查不到订阅时，行为明确且可观测，不可静默误成功

---

## WP-7 接通 admin subscriptions 数据链路

### 问题来源
- AI-1 主评审
- AI-2 补充评审

### 目标文件
- `market-blockchain/internal/api/router.go`
- `market-blockchain/internal/api/handlers/admin/subscription_handler.go`
- `market-blockchain/web/admin/index.html`

### 要解决的问题
前端请求 subscriptions 列表，但后端链路不完整或未注册。

### 实现要求
- 注册 `GET /admin/api/v1/subscriptions`
- 正确注入 handler
- 保证字段与前端渲染字段一致
- limit / 空结果 / 错误路径语义明确
- 禁止 handler 吞掉 repository 错误后继续返回伪成功

### 验收标准
- admin 页面可真实加载 subscription 列表
- 流量字段可展示
- 路由不再 404
- DB 异常时不会误返回成功假数据

---

## WP-8 为关键多步更新补事务边界

### 问题来源
- 设计质量评审
- 生命周期补充评审

### 目标文件
- `market-blockchain/internal/service/subscription_service.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/renewal_service.go`
- `market-blockchain/internal/service/subscription_upgrade_service.go`
- 仓储层事务封装相关文件

### 要解决的问题
创建、首次扣费、续费、升级都存在多表更新，但没有事务边界。

### 实现要求
以下流程至少需要单事务保护：
- 创建订阅
- 首次扣费激活
- 自动续费
- 升级订阅

### 特别说明
- 外部副作用（链上、Xray）不要直接混进 DB 事务中做裸串行调用
- 若无法一次完成完整 saga/outbox，也必须先保证 DB 内部状态一致

### 验收标准
- 任一步 DB 更新失败时不会留下半完成状态
- event 写入与主状态更新要么一起成功，要么一起回滚

---

## WP-9 修复续费、过期、升级、降级闭环

### 问题来源
- 生命周期补充评审文档

### 目标文件
- `market-blockchain/internal/service/renewal_service.go`
- `market-blockchain/internal/service/subscription_upgrade_service.go`
- `market-blockchain/internal/api/handlers/subscription_upgrade_handler.go`

### 要解决的问题
续费像内部记账，不是完整支付闭环；过期不移除 Xray；升级降级缺少一致性保护。

### 实现要求
#### 续费
- 明确续费成功的权威信号是什么
- 如果真实扣费由链上决定，则 period 延长必须依赖真实成功
- allowance 不足导致过期时，必须接入 `RemoveUser`

#### 升级
- 明确是“立即支付立即生效”还是“待支付后生效”
- charge / subscription / authorization / event 一致性必须受保护

#### 降级
- `PendingPlanID` 的延迟生效语义必须清晰
- renewal 应用 pending plan 时必须有一致性保证

#### handler 错误语义
- `not found` -> 404
- 非法状态 / 非法升级降级 -> 400 / 409 / 422
- 仅内部错误 -> 500

### 验收标准
- 生命周期不再只是局部改字段
- 升级/降级/续费具备明确时序语义与错误语义

---

## WP-10 修复 scheduler / shutdown 稳定性

### 问题来源
- 设计质量评审

### 目标文件
- `market-blockchain/internal/scheduler/scheduler.go`
- `market-blockchain/internal/app/app.go`

### 要解决的问题
`Stop()` 非幂等，重复 shutdown 可能 panic。

### 实现要求
- `Scheduler.Stop()` 改为幂等
- `App.Shutdown()` 支持重复调用
- 后台任务退出路径清晰
- 若有 ticker / goroutine，必须可被可靠停止

### 验收标准
- 连续多次 shutdown 不 panic
- 后台任务能正常停止

---

## WP-11 修复 repository context 设计与事件可靠性

### 问题来源
- 设计质量评审

### 目标文件
- `market-blockchain/internal/repository/*.go`
- `market-blockchain/internal/store/postgres/*.go`
- `market-blockchain/internal/service/*.go`

### 要解决的问题
核心 repository 方法 context 设计不一致，event 写入错误被忽略。

### 实现要求
- 核心 repository 方法统一支持 `context.Context`
- service 层贯穿传递 context
- 所有 `events.Create(...)` 错误必须显式处理
- 能纳入事务的 event 写入应纳入事务

### 验收标准
- shutdown / timeout / request cancel 能传递到关键 DB 路径
- event 失败不再被静默忽略

---

## WP-12 核实并修复 admin 安全边界

### 问题来源
- AI-2 补充评审

### 目标文件
- `market-blockchain/internal/api/router.go`
- `market-blockchain/internal/api/handlers/admin/*.go`
- admin middleware / auth 相关文件
- `market-blockchain/web/admin/index.html`

### 要解决的问题
从代码上看，admin API 与 admin UI 可能直接裸露。

### 实现要求
至少完成以下二选一中的一个，并在文档写明：

#### 方案 A：本轮直接补最小认证
- 加入明确的 auth middleware
- admin UI 与 admin API 同时受保护

#### 方案 B：本轮不能补认证时
- 在代码与文档里明确标记“仅限受控内网 / 临时环境”
- 至少不要让此边界继续处于未知状态

### 补充要求
- 不允许 admin handler 吞错并返回伪成功
- 核实 plan 管理等写接口是否同样裸露

### 验收标准
- admin 暴露面有明确结论
- 不再处于“可能裸露但无人确认”的状态

---

## WP-13 补数据库约束与数据模型清理

### 问题来源
- 设计质量评审

### 目标文件
- `market-blockchain/internal/store/migrations/*.sql`
- event repository / event migration 相关文件

### 要解决的问题
状态字段无 CHECK，业务唯一性弱，event 结构不利于审计。

### 实现要求
#### schema 约束
- 为关键状态字段增加 CHECK 约束：
  - `subscriptions.status`
  - `charges.status`
  - `authorizations.permit_status`
  - `events.type`（如合适）
- 评估并补充关键业务唯一约束

#### event 结构
- 评估是否在本轮加入结构化 `subscription_id`
- 至少不要继续依赖 `metadata LIKE` 作为唯一审计查询手段

### 验收标准
- 非法状态写入会被数据库拒绝
- event 查询能力不再完全依赖弱文本匹配

---

## 7. 测试任务

本轮至少补以下测试，测试优先级不能低于代码修复优先级。

### T1 创建订阅链路测试
- 创建成功 -> 数据真实存在
- 中途失败 -> 事务回滚
- 创建后查询 -> 可读

### T2 首次激活与状态迁移测试
- `pending -> active`
- 激活成功 -> Xray AddUser 被调用
- 激活失败 -> 状态与外部副作用行为符合定义

### T3 续费 / 过期 / 升级 / 降级测试
- renewal success
- allowance 不足 -> expired -> RemoveUser
- upgrade success / partial failure
- downgrade 延迟生效
- renewal 时应用 `PendingPlanID`

### T4 流量采集与入库测试
- Query 成功 -> DB 更新
- 查不到订阅 -> 明确行为
- DB 更新失败 -> 错误处理正确

### T5 Admin API 测试
- subscriptions 列表返回 200
- 字段包含流量字段
- repo error 不返回伪成功
- 认证边界按预期生效

### T6 Shutdown / scheduler 测试
- 重复 shutdown 不 panic
- 后台任务可停止
- 停机时 context/cancel 传递正常

---

## 8. AI 修复时的边界要求

### 每次只做一个工作包或一组强相关工作包
避免一个 AI 同时跨太多模块修改，导致问题难以验证。

### 每次修改后必须验证
最低要求：
```bash
go test ./...
```

如果涉及 Xray 集成测试，再补：
```bash
go test -tags=integration ./internal/xray/...
```

### 每个工作包完成后都要回写
- 修改了哪些文件
- 解决了哪个工作包
- 哪些风险仍未解决
- 需要下一个 AI 接什么任务

### 文档同步规则
只有工作包通过代码与测试验证后，才允许更新：
- `docs/V2_design/PROJECT_OVERVIEW.md`
- `market-blockchain/docs/XRAY_SETUP.md`
- `market-blockchain/docs/TESTING.md`
- `docs/V2_design/implementation/phase3_traffic_integration_complete.md`

---

## 9. 推荐的 AI 执行顺序

### 第一批先做
1. `WP-1` 创建订阅链路真实落库
2. `WP-2` 修复首次激活链路
3. `WP-8` 创建/激活链路事务化
4. `WP-3` 统一生命周期状态机入口

### 第二批再做
5. `WP-4` Xray 技术路线 + client 实现
6. `WP-5` 接入 Xray 同步
7. `WP-6` 修复流量映射
8. `WP-7` 接通 admin subscriptions 链路

### 第三批稳定性与安全
9. `WP-10` shutdown / scheduler
10. `WP-11` context / event 可靠性
11. `WP-12` admin 安全边界
12. `WP-13` schema / event 模型补强

### 最后统一补
13. 测试任务 `T1 ~ T6`
14. 文档修正

---

## 10. 最终验收口径

只有当以下条件同时满足，才能认为本轮修复完成：

### 业务闭环
- 创建、激活、取消、过期、续费至少单链路真实可用
- Xray 同步与 DB 状态不再明显脱节
- 流量采集可真实入库
- admin 页面可真实展示订阅/流量数据

### 稳定性
- 创建/首次扣费/续费/升级具备事务边界
- shutdown 重复调用不 panic
- event 写入不再静默丢失

### 安全与接口语义
- admin 暴露面有明确结论与保护策略
- 业务错误与系统错误有基本区分

### 测试
- 至少覆盖主成功路径和关键失败路径
- 不再依赖大面积 `Skip` 来宣称完成

### 文档
- 不再出现“代码没闭环，文档却写完成”的情况

---

## 11. 一句话执行策略

> **先把订阅生命周期和 Xray 主链路修成真实闭环，再修一致性与安全边界，最后补测试并回收夸大的文档状态。**
