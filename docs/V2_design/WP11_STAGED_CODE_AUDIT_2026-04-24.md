# WP-11 Staged 代码审计报告（2026-04-24）

**审计对象**: 当前已 staged 的 `WP-11 第一阶段：context 贯穿与生命周期/Xray 调用链收口` 实现  
**审计日期**: 2026-04-24  
**审计结论**: **可以认定为“核心目标已完成并达到本轮验收标准”，但仍保留一项明确的上下文传播设计债：DB 事务内部 SQL 执行尚未继续使用 `ctx`。**

---

## 1. 审计范围

本次审计基于当前 staged diff，涉及文件：

- `market-blockchain/internal/api/handlers/subscription_handler.go`
- `market-blockchain/internal/api/handlers/subscription_upgrade_handler.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/chain_service_test.go`
- `market-blockchain/internal/service/renewal_service.go`
- `market-blockchain/internal/service/subscription_lifecycle_service.go`
- `market-blockchain/internal/service/subscription_lifecycle_service_test.go`
- `market-blockchain/internal/service/subscription_management_service.go`
- `market-blockchain/internal/service/subscription_service.go`
- `market-blockchain/internal/service/subscription_service_test.go`
- `market-blockchain/internal/service/subscription_upgrade_service.go`
- `market-blockchain/internal/store/postgres/postgres.go`
- `market-blockchain/internal/store/postgres/postgres_test.go`

对照文档：

- `docs/V2_design/PHASE2_PHASE3_REMEDIATION_DEVELOPMENT_GUIDE.md`
- `docs/V2_design/WP5_STAGED_CODE_AUDIT_2026-04-24.md`

---

## 2. 总体判断

这次 staged 修改已经**实质性完成了 WP-11 第一阶段最核心的目标**：

1. HTTP handler 已把 `r.Context()` 继续向下传递
2. service 间调用链已统一改为显式接收 `context.Context`
3. `SubscriptionLifecycleService` 不再在 Xray 同步路径里私自使用 `context.Background()`
4. store 的事务入口已改为 `BeginTx(ctx, nil)`，不再完全脱离调用方上下文
5. 相关单元测试与 store 测试已同步更新
6. `go test ./...` 在 `market-blockchain` 模块内通过

因此，可以明确地说：

> **系统已经从“生命周期/Xray 关键路径内部重新起一个脱离请求的背景上下文”，推进到“核心调用链显式接收并继续传递调用方 context”。**

这正是本轮 WP-11 第一阶段的主要目标。

但也需要明确一个边界：

- 当前只是把 `ctx` 传到了事务开启点和 Xray 调用点
- **事务内部的 SQL 执行仍然使用 `tx.Exec(...)`，不是 `tx.ExecContext(ctx, ...)`**
- 因此，DB 层的上下文传播还没有完全闭环

所以更准确的结论是：

> **WP-11 第一阶段已完成“服务链路与 Xray 路径的上下文显式贯穿”，但数据库事务内部的 SQL 级上下文传播仍停留在半完成状态。**

---

## 3. 验证结果

### 3.1 最低验证命令

已执行：

```bash
cd "/Users/hyperorchid/MeshNetProtocol/openmesh-cli/market-blockchain" && go test ./...
```

结果：**通过**

### 3.2 与 WP-11 第一阶段目标对照

#### 目标 1：生命周期关键方法显式接收 `context.Context`
- **当前判断**：**成立**
- **说明**：`CreatePendingSubscription(...)`、`CompleteFirstCharge(...)`、`CancelSubscription(...)`、`ExpireSubscription(...)`、`ApplyRenewalSuccess(...)`、`ApplyImmediateUpgrade(...)`、`ScheduleDowngrade(...)` 均已改为显式接收 `ctx`

#### 目标 2：HTTP 请求上下文可进入生命周期主链路
- **当前判断**：**成立**
- **说明**：handler 层已改为把 `r.Context()` 传给 subscription create/cancel/upgrade/downgrade 等入口

#### 目标 3：Xray 调用不再绕过上传下来的上下文
- **当前判断**：**成立**
- **说明**：`syncActiveSubscription(...)` 与 `syncInactiveSubscription(...)` 已改为接收 `ctx` 并直接透传给 `AddUser(...)` / `RemoveUser(...)`

#### 目标 4：事务入口开始使用上下文
- **当前判断**：**部分成立**
- **说明**：`postgres.Store` 已从 `Begin()` 改为 `BeginTx(ctx, nil)`，但事务内部 SQL 仍使用 `tx.Exec(...)` 而不是 `tx.ExecContext(ctx, ...)`

#### 目标 5：改动应保持现有业务语义不回退
- **当前判断**：**成立**
- **说明**：本次修改主要是函数签名与上下文透传，未改变前几轮已建立的生命周期/Xray 语义；测试通过也支持这一判断

---

## 4. 本次修改的主要优点

### 4.1 上下文传递终于从 HTTP 入口贯通到生命周期核心路径

这是本轮最重要的正向结果。

现在请求进入后，不再是：

- handler 收到 `r.Context()`
- service 内部却在关键节点重新脱离上下文

而是逐层继续向下传递：

- handler
- service
- lifecycle service
- Xray / store

这使得后续：

- 请求取消
- 超时控制
- shutdown 收敛
- trace / logging 统一

都有了真正可继续推进的基础。

---

### 4.2 本轮修改是“外科式”的，没有破坏既有生命周期语义

本次 diff 的主要性质是：

- 函数签名改造
- 调用链透传 `ctx`
- store 事务入口换成 `BeginTx(ctx, nil)`

而不是趁机重写业务逻辑。

这点是对的，因为本轮目标本来就不是：

- 重做事务框架
- 重写 event 模型
- 引入重试/补偿
- 重构 repository 全栈接口

因此当前实现保持了较好的任务边界控制。

---

### 4.3 Xray 同步路径不再私自使用 `context.Background()`

这是对 WP-5 明确设计债的直接修复。

此前问题在于：

- 上层即使已经有请求级 `ctx`
- 生命周期服务在 Xray 调用处仍重新起 `context.Background()`

这样会导致：

- 请求取消无法向下游传播
- 超时语义被切断
- 后续统一治理困难

现在这条明显错误的边界已经被修正。

---

### 4.4 store 事务入口开始具备上下文感知能力

`postgres.Store` 从：

- `DB.Begin()`

改成：

- `DB.BeginTx(ctx, nil)`

虽然这还不是完整终态，但它至少把事务的建立动作纳入了上下文管理范围内，方向是正确的，也和后续进一步做 `ExecContext` / `QueryContext` 保持一致。

---

### 4.5 测试同步更新，说明这不是“只改签名不护回归”

本轮不是简单机械改函数签名。

可以看到：

- service tests 已全部切换到传入 `context.Background()`
- store tests 也同步更新到了带 `ctx` 的调用方式
- 生命周期测试桩里新增了 `lastCtx` 字段，为后续进一步补“是否真的传递到下层”的断言留下了空间

这说明实现至少考虑到了最小回归保护。

---

## 5. 高优先级问题

### P1-1：数据库事务内部 SQL 执行尚未继续使用 `ctx`，上下文传播只完成了一半

#### 现象

当前 `postgres.Store` 已改成：

```go
tx, err := s.DB.BeginTx(ctx, nil)
```

但事务内部仍然大量使用：

```go
tx.Exec(...)
```

而不是：

```go
tx.ExecContext(ctx, ...)
```

#### 为什么这是问题

这意味着：

- `ctx` 只参与了“开启事务”这一步
- 后续具体 SQL 执行并没有继续受该 `ctx` 约束
- 如果请求在事务处理中被取消，当前实现未必能在每条 SQL 层面及时响应

也就是说，当前实现确实比之前更好，但还没有达到“数据库操作链路完整受上下文控制”的程度。

#### 影响评估

这**不是本轮拒绝验收的理由**，因为 WP-11 第一阶段本来就强调“最小升级、不要全栈大改”。

但必须明确：

> **当前完成的是 context 贯穿的主骨架，不是 DB 层上下文传播的最终闭环。**

#### 建议修复

后续下一小步建议优先把 `postgres.Store` 事务方法中的：

- `tx.Exec(...)`

逐步替换为：

- `tx.ExecContext(ctx, ...)`

如果还有查询，则同样统一到 `QueryContext` / `QueryRowContext`。

这是最自然、也最小的后续收口方向。

---

## 6. 中优先级设计问题

### P2-1：当前测试已记录 `lastCtx`，但还没有真正断言“传下去的是同一个 ctx”

本轮测试桩里已经新增：

- `store.lastCtx`
- `xraySync.lastCtx`

这是对的。

但目前从 staged 测试看，主要还是把调用改成了传 `context.Background()`，并没有进一步断言：

- lifecycle service 收到的 ctx 是否真的传到了 store
- 同一个 ctx 是否真的传到了 xray client

因此，当前测试更多是在保证“签名统一、可编译、可运行”，还没有把“透传正确性”锁死。

这不阻断本轮，但它是一个很值得补上的回归保护点。

---

### P2-2：`SubscriptionLifecycleService` 的成功/失败事件写入仍未接收 `ctx`

虽然 Xray 调用和 store 事务入口已开始接入上下文，但：

- `subscriptions.Update(...)`
- `events.Create(...)`
- `recordXraySyncEvent(...)`

这些 repository 写入路径仍然不是 context-aware 接口。

这意味着当前系统存在一种“半 context-aware”状态：

- 一部分路径已经接通
- 另一部分路径仍然是旧接口

这也是本轮提示词刻意允许的结果，因为目标是“第一阶段最小改造”。

但它说明后续若继续做 WP-11 后续阶段，repository 层仍需要有选择地继续收口。

---

## 7. 测试审计评价

### 已覆盖的内容

当前 staged 测试已经覆盖了：

1. service 层主要入口已切换到新签名
2. lifecycle 测试桩与 store 测试桩已兼容 `ctx`
3. store 事务方法改签名后仍能通过原有 commit/rollback 测试
4. `go test ./...` 在模块内通过

### 仍建议补充的关键测试

后续建议补这些更贴近本轮目标的用例：

1. **ctx 透传一致性测试**
   - 给一个自定义 ctx 值
   - 断言 `store.lastCtx == ctx`
   - 断言 `xraySync.lastCtx == ctx`

2. **ctx cancel 对 Xray 路径的行为测试**
   - 至少在 mock 层证明取消上下文会被下游收到

3. **如果继续推进 DB 层**
   - 在 store 层改成 `ExecContext` 后，再补“事务执行过程中上下文取消”的边界测试

---

## 8. 与前次审计的关系

### 与 WP-5 的关系

`WP-5` 的核心结论之一是：

- 生命周期与 Xray 同步已经接通
- 但 `SubscriptionLifecycleService` 中还存在 `context.Background()` 设计债

本轮正是直接修这条债务的第一阶段：

- 不改变 WP-5 的同步语义
- 只把上下文贯穿起来

因此，这次修改可以视为：

> **在不推翻 WP-5 的前提下，把 Xray 同步从“语义正确但上下文断裂”推进到了“语义正确且开始尊重调用方上下文”。**

### 与 WP-8 的关系

`WP-8` 的重点是事务边界收口。

本轮没有重做 WP-8，但把 store 的事务入口进一步升级为 `BeginTx(ctx, nil)`，说明：

- WP-8 建立的事务收口方向被保留
- WP-11 第一阶段是在其基础上继续增强上下文能力

这条演进路径是合理且连续的。

---

## 9. 建议给后续 AI 的工作顺序

### 本轮可以接受为“WP-11 第一阶段核心完成”

建议采用下面这个口径：

> 已将 HTTP handler、service、lifecycle service、Xray 调用与事务入口改为显式接收并传递 `context.Context`，修复了此前在生命周期/Xray 关键路径中重新使用 `context.Background()` 的问题；模块测试也已通过。因此，WP-11 第一阶段要求的“主调用链 context 贯穿”已经成立。但数据库事务内部 SQL 仍未统一切换到 `ExecContext`，repository/event 写入层也还未全面 context-aware，所以上下文传播仍未完全闭环。

### 下一轮优先建议

建议后续优先顺序：

1. **补 DB 事务内部 `ExecContext` / `QueryContext`**
   - 这是最自然的下一小步
   - 也是当前最明确的剩余缺口

2. **补 ctx 透传断言测试**
   - 把“能编译运行”升级成“确实透传同一个 ctx”

3. **视范围决定是否继续 repository 层 context 化**
   - 尤其是 event 写入与 subscription update 这些生命周期关键路径

4. **不要在这一步引入 outbox/retry/saga 等大方案**
   - 那会明显超出当前任务边界

---

## 10. 最终审计结论

**结论一句话：**

> 这次 staged 修改已经实质性完成了 `WP-11` 第一阶段的核心目标：`context.Context` 已从 HTTP 入口显式贯穿到 subscription/lifecycle/Xray/store 关键调用链，`SubscriptionLifecycleService` 中此前直接使用 `context.Background()` 的问题已被修复，且 `go test ./...` 在 `market-blockchain` 模块内通过。与此同时，数据库事务内部 SQL 仍未继续使用 `ExecContext`，因此当前应按“主链路 context 贯穿已完成、DB 层上下文闭环仍待下一步补齐”来验收。
