# WP-2 Staged 代码审计报告（2026-04-24）

**审计对象**: 当前已 staged 的 `WP-2 修复首次激活链路` 实现  
**审计日期**: 2026-04-24  
**审计结论**: **可以认定为“已明显修复核心查询缺陷并通过最低测试门槛”，但暂不建议按“完全闭环”验收；仍存在 2 个高优先级业务一致性问题与若干后续设计债。**

---

## 1. 审计范围

本次审计基于当前 staged diff，涉及文件：

- `market-blockchain/internal/app/app.go`
- `market-blockchain/internal/repository/authorization_repository.go`
- `market-blockchain/internal/repository/charge_repository.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/chain_service_test.go`
- `market-blockchain/internal/service/subscription_service_test.go`
- `market-blockchain/internal/store/postgres/authorization_repository.go`
- `market-blockchain/internal/store/postgres/charge_repository.go`
- `market-blockchain/internal/store/postgres/postgres.go`
- `market-blockchain/internal/store/postgres/postgres_test.go`

对照文档：

- `docs/V2_design/PHASE2_PHASE3_REMEDIATION_DEVELOPMENT_GUIDE.md` 中 `WP-2`
- `docs/V2_design/code_review_ai1_功能实现与业务正确性评审_补充-订阅生命周期与状态流转.md`

---

## 2. 总体判断

这次 staged 修改**已经实质性修复了 WP-2 的核心问题**，尤其是最初评审里指出的这条致命缺陷：

- 不再使用 `GetByIdentityAndPlan("", "")`
- 不再使用 `GetByChargeID("")`
- 改为通过明确主键：
  - `authorizations.GetByID(input.AuthorizationID)`
  - `charges.GetByID(input.ChargeRecordID)`

同时，它还做了几件正确的事：

1. 增加了 authorization / charge 的按 ID 查询接口与 postgres 实现
2. 在 `ExecuteFirstCharge()` 中补了 subscription / authorization / charge 之间的归属校验
3. 把首次激活成功后的多表更新与 event 写入收敛进 `CompleteFirstCharge(...)` 事务
4. 补了 service 层和 store 层的测试
5. 当前 `go test ./...` 已通过

**所以：WP-2 的“最核心修复目标”已达成。**

但是，这次实现还没有达到“生命周期激活闭环已经可靠完成”的程度，主要因为还存在两类重要问题：

- **链上成功 / DB 失败时的一致性断裂没有明确定义**
- **首次激活缺少必要的前置状态校验**

因此，更准确的判断是：

> **WP-2 已修掉最致命的查询缺陷，并建立了一个基本可工作的首次激活链路；但它还没有把首次激活做成“严格可靠的业务闭环”。**

---

## 3. 验证结果

### 3.1 最低验证命令
已执行：

```bash
go test ./...
```

结果：**通过**

### 3.2 与 WP-2 验收标准对照

#### 验收项 1：首次扣费成功时，`pending -> active` 可靠成立
- **当前判断**：**基本成立，但有条件**
- **说明**：成功路径上已实现 `subscription.Status = active`，并通过事务统一写回；但缺少“只能从 pending 激活”的硬校验，因此“可靠”还不够强

#### 验收项 2：`charge / authorization / subscription` 状态一致
- **当前判断**：**成功路径基本成立，失败路径仍不完整**
- **说明**：成功时三者状态一并更新；但当链上 permit 成功、后续 charge 失败时，DB 中 authorization 状态未同步成已授权，会与链上事实脱节

#### 验收项 3：查询路径具备明确业务语义
- **当前判断**：**成立**
- **说明**：已改为按主键查询，不再依赖空字符串伪查询

---

## 4. 本次修改的主要优点

### 4.1 核心查询缺陷已被直接修复
这是本次最重要的正向结果。

旧问题是：

- authorization 用空 identity / 空 plan 查
- charge 用空 chargeID 查
- 再回头比对 ID

新实现已经改为：

- `GetByID(input.AuthorizationID)`
- `GetByID(input.ChargeRecordID)`
- 之后再做归属校验

这让首次激活链路第一次具备了**明确、可理解、可测试的查询语义**。

---

### 4.2 多表成功更新被收进一个事务
新增：

- `Store.CompleteFirstCharge(subscription, authorization, charge, event)`

它把以下动作放入同一事务：

1. 更新 `authorizations`
2. 更新 `charges`
3. 更新 `subscriptions`
4. 写入 `events`

这明显优于之前分散在 service 里的裸串行更新，也符合修复指南里“至少先把 DB 内部一致性收住”的方向。

---

### 4.3 补了关键归属关系校验
当前实现增加了这些检查：

- `charge.AuthorizationID == authorization.ID`
- `charge.SubscriptionID == input.SubscriptionID`
- `subscription.CurrentAuthorizationID` 与 authorization 一致
- `subscription.LastChargeID` 与 charge.ChargeID 一致

这能有效避免“查到了对象，但对象彼此并不属于同一条业务链路”的错误激活。

---

### 4.4 测试覆盖比 WP-1 明显更扎实
相比 WP-1，这次测试质量明显提升：

- `go test ./...` 已通过
- service 测试覆盖了成功路径、缺失对象、持久化失败、链上 charge 失败等场景
- store 测试覆盖了事务 commit / rollback

这使得本次修复具备了最基本的可回归性。

---

## 5. 高优先级问题

### P1-1：permit 成功后如果 charge 失败，DB 中 authorization 状态会与链上事实脱节

#### 现象
当前流程是：

1. 先调用 `AuthorizeChargeWithPermit(...)`
2. 如果成功，拿到 `permitTxHash`
3. 再调用 `Charge(...)`
4. 只有 charge 成功后，才把 authorization 状态更新为：
   - `PermitStatus = completed`
   - `PermitTxHash = ...`
   - `AuthorizedAllowance = TargetAllowance`

但如果第 3 步失败：

- 代码只会把 `charge.Status` 标成 `failed`
- **不会把 authorization 的“链上授权已成功”同步到 DB**

#### 为什么这是问题
链上 permit 已经发生成功事实，但数据库里 authorization 仍可能保留：

- `pending`
- 空 `permit_tx_hash`
- 未更新的 `authorized_allowance`

这会造成：

> **链上状态已经变了，DB 却仍然描述成“未授权完成”。**

这违反了本轮修复最核心的“业务语义真实”目标。

#### 影响
- 首次激活失败后的补偿、重试、排障会读到错误状态
- 后续如果要依赖 authorization 状态做续费或补偿决策，可能走错分支
- 审计层面也会错误理解这次首次激活到底失败在哪一步

#### 建议修复
至少二选一明确下来：

##### 方案 A：最小修复
当 permit 成功但 charge 失败时，仍持久化 authorization 的成功状态：
- `PermitStatus = completed`
- `PermitTxHash = permitTxHash`
- `AuthorizedAllowance = TargetAllowance`

同时将 charge 标记为 failed，并记录 event 或错误日志说明“授权成功、扣费失败”。

##### 方案 B：更完整修复
把“permit 成功、charge 失败”的状态定义为一个明确中间态或待补偿态，由后续补偿/重试机制接手。

当前项目阶段更适合先做 **方案 A**，至少不要让 DB 明显失真。

---

### P1-2：缺少前置状态校验，首次激活并没有被严格限制在 `pending -> active`

#### 现象
当前实现会检查对象归属，但**没有显式限制这些前置状态**：

- `subscription.Status` 是否必须是 `pending`
- `charge.Status` 是否必须是 `pending`
- `authorization.PermitStatus` 是否必须是 `pending`

#### 为什么这是问题
按修复文档，WP-2 的语义不是“任意时候触发一次 charge”，而是：

> **首次扣费成功后，subscription 从 `pending` 进入 `active`**

如果没有前置状态限制，那么理论上可能发生：

- 已经 active 的订阅再次执行首次激活
- 已取消 / 已过期订阅被错误重新激活
- 已完成或已失败的 charge 再次被执行
- 已完成授权的 authorization 被重复走首次授权流程

#### 影响
这会让“首次激活”这个动作失去业务边界，后续也更难统一成状态机入口。

#### 建议修复
在 `ExecuteFirstCharge()` 开头显式校验：

- `subscription.Status == pending`
- `charge.Status == pending`
- `authorization.PermitStatus == pending`

不满足时返回明确业务错误，而不是继续调用链上动作。

---

## 6. 中优先级设计问题

### P2-1：链上成功后 DB 持久化失败，当前没有定义恢复策略

#### 现象
当前流程里：

- permit 和 charge 都是先在链上执行
- 然后才调用 `completer.CompleteFirstCharge(...)` 落库

如果链上两步都成功，但 `CompleteFirstCharge(...)` 失败，则会返回：

```go
persist first charge completion: ...
```

#### 为什么这是问题
这意味着：

- 链上已成功
- DB 仍可能保持 `pending`
- event 未写入

也就是典型的“外部副作用已发生，内部状态未落地”。

#### 结论
这并不是本次单独要完全解决的问题，因为修复指南自己也承认：

- 先保证 DB 内部一致性
- saga/outbox 可以后补

但这里必须明确：

> **当前实现只是把 DB 内部一致性收住了，并没有解决跨链上 / DB 的一致性问题。**

#### 建议修复
在后续 `WP-8 / WP-11 / WP-5` 中，至少明确一种策略：

- 标记待补偿
- 后台重试
- 失败事件入库
- 或显式 degraded mode 语义

当前不能把这条链路宣传成“完整闭环”。

---

### P2-2：`ChainService` 中的 `events` 依赖已不再参与主成功路径

当前 `ChainService` 仍持有：

- `events repository.EventRepository`

但成功路径已经不再直接用它，而是通过 `completer.CompleteFirstCharge(...)` 把 event 写入事务。

这说明现在的设计处于一种过渡态：

- 一部分事件逻辑走 `events.Create(...)`
- 一部分走 store 事务批量方法

这和 WP-1 审计中指出的问题是一致的：

> 事务收敛方向是对的，但 repository / store 双轨并存会让后续统一更困难。

建议在 WP-1 / WP-2 回修时一起做小范围收口，不要长期维持这种混搭状态。

---

### P2-3：事务方法仍然没有 context，和后续 WP-11 方向不一致

`CompleteFirstCharge(...)` 仍使用：

- `s.DB.Begin()`
- `tx.Exec(...)`

没有 `context.Context`。

这不会阻断 WP-2，但后续做 shutdown / request cancel / timeout 贯穿时，还要返工。

建议后续统一为：

- `BeginTx(ctx, ...)`
- `ExecContext(ctx, ...)`

---

## 7. 测试审计评价

### 已覆盖的内容
这次测试已经覆盖：

- 成功激活
- authorization 缺失
- charge 缺失
- 持久化失败
- 链上 charge 失败
- store 层事务 commit / rollback

### 仍缺的关键测试
建议后续补这些更贴近业务语义的用例：

1. **subscription 不是 pending 时拒绝首次激活**
2. **charge 不是 pending 时拒绝首次激活**
3. **authorization 不是 pending 时拒绝首次激活**
4. **permit 成功但 charge 失败时，authorization 状态如何落库**
5. **subscription / charge / authorization 归属不一致时的错误语义**

---

## 8. 与前次 WP-1 审计的关系

这次 WP-2 修改还顺手修复了上次 WP-1 审计中的一个阻断项：

- `subscription_service_test.go` 里缺失的 `GetByID` stub 已补上
- 当前 `go test ./...` 可以通过

这是正向改进。

但 WP-1 审计里提到的另外几个问题仍然没有自动消失，尤其是：

- 创建后按 ID 读回的真实验证还不充分
- repository / store 双轨事务抽象问题依旧存在

所以后续最好把 `WP-1` 和 `WP-2` 的回修放在同一轮处理。

---

## 9. 建议给后续 AI 的回修顺序

### 本轮可以先接受为“WP-2 核心修复已完成”
前提是你接受下面这个表述口径：

> 已修复最关键的查询错误，并建立了基本可工作的首次激活路径，但仍有一致性与状态机边界问题待回收。

### 下一轮优先回修
建议优先顺序：

1. **补前置状态校验**
   - 严格限定 `pending -> active`
2. **修 permit 成功 / charge 失败时的 authorization 落库语义**
3. **把 WP-1 / WP-2 的事务抽象一起小范围收口**
4. **再考虑 context 统一与补偿策略**

---

## 10. 最终审计结论

**结论一句话：**

> 这次 staged 修改已经实质性完成了 `WP-2` 最关键的修复目标：首次激活不再依赖空字符串伪查询，`pending -> active` 的成功路径也已被代码与测试打通；但它仍未彻底解决首次激活链路在失败路径上的业务真实性问题，尤其是“permit 成功但 charge 失败”的状态失真，以及缺少严格前置状态校验，因此建议按“核心修复完成、仍需一轮回修”来处理，而不是宣称生命周期闭环已经完成。
