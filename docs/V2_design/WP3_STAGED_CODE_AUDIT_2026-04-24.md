# WP-3 Staged 代码审计报告（2026-04-24）

**审计对象**: 当前已 staged 的 `WP-3 统一订阅生命周期状态机入口` 实现  
**审计日期**: 2026-04-24  
**审计结论**: **可以认定为“已完成最小生命周期入口收敛，并通过最低测试门槛”，建议按“核心目标已完成、但仍保留事务闭环与外部副作用设计债”验收。**

---

## 1. 审计范围

本次审计基于当前 staged diff，涉及文件：

- `market-blockchain/internal/domain/subscription.go`
- `market-blockchain/internal/service/subscription_lifecycle_service.go`
- `market-blockchain/internal/service/subscription_service.go`
- `market-blockchain/internal/service/subscription_management_service.go`
- `market-blockchain/internal/service/chain_service.go`
- `market-blockchain/internal/service/renewal_service.go`
- `market-blockchain/internal/service/subscription_upgrade_service.go`
- `market-blockchain/internal/service/subscription_service_test.go`
- `market-blockchain/internal/service/chain_service_test.go`
- `market-blockchain/internal/app/app.go`

对照文档：

- `docs/V2_design/PHASE2_PHASE3_REMEDIATION_DEVELOPMENT_GUIDE.md` 中 `WP-3`
- `docs/V2_design/code_review_ai1_功能实现与业务正确性评审_补充-订阅生命周期与状态流转.md`
- `docs/V2_design/WP1_STAGED_CODE_AUDIT_2026-04-24.md`
- `docs/V2_design/WP2_STAGED_CODE_AUDIT_2026-04-24.md`

---

## 2. 总体判断

这次 staged 修改**已经实质性完成了 WP-3 的最小目标**：

> **把原本分散在多个 service 中的关键订阅生命周期状态迁移，收敛到更明确的 domain + lifecycle service 入口上。**

和修复指南中的目标对照，这次改动已经做到：

1. 在 `domain.Subscription` 中补了最小状态迁移语义：
   - `Activate(now)`
   - `Cancel(now)`
   - `Expire(now)`
2. 新增 `SubscriptionLifecycleService`，作为生命周期关键入口协调层
3. 创建订阅、首次激活、取消、过期、续费成功、升级、降级都已改为优先经过统一入口
4. `app.go` 中的依赖注入也已切换为由业务 service 依赖 lifecycle service
5. 当前 `go test ./...` 已通过

因此，如果只以 `WP-3` 在修复指南中的目标来判断：

> **“不要再由多个 service 各自偷偷改 `subscription.Status`，而是收敛成少量明确入口”**

那么这次实现可以认为**已经达标**。

但也必须明确：

- 这次完成的是**生命周期语义入口收敛**，不是完整的生命周期闭环完成
- 续费 / 升级等链路虽然被纳入统一入口，但**事务一致性问题没有被同时解决**
- Xray 相关语义仍然只是占位，没有形成真实副作用闭环

所以更准确的结论是：

> **WP-3 已完成“语义收敛”这一步，但还不能把项目表述成“生命周期闭环已完全可靠”。**

---

## 3. 验证结果

### 3.1 最低验证命令
已执行：

```bash
go test ./...
```

结果：**通过**

### 3.2 与 WP-3 验收标准对照

#### 验收项 1：代码中不再出现多个 service 各自偷偷改 `subscription.Status`
- **当前判断**：**基本成立**
- **说明**：创建、首次激活、取消、过期这几条关键链路已经明显改为走 `SubscriptionLifecycleService` / `domain.Subscription` 语义入口；从当前 staged diff 看，核心生产路径中的散写状态已显著收敛

#### 验收项 2：生命周期关键路径具备统一业务语义
- **当前判断**：**成立，但仍是“最小统一”**
- **说明**：统一入口已经形成，但续费 / 升降级仍只是接入统一协调层，并没有随之获得完整事务与外部副作用闭环

---

## 4. 本次修改的主要优点

### 4.1 在 domain 层补上了明确的最小状态迁移语义
这是本次最重要的结构性改进。

`Subscription` 新增：

- `Activate(now)`：仅允许 `pending -> active`
- `Cancel(now)`：仅允许 `active -> cancelled`
- `Expire(now)`：仅允许 `active -> expired`
- 非法迁移统一返回 `ErrInvalidSubscriptionTransition`

这比之前各个 service 直接写：

- `subscription.Status = ...`
- `subscription.UpdatedAt = ...`

更清晰，也更接近真正的领域语义。

---

### 4.2 引入了薄协调层 `SubscriptionLifecycleService`
这次没有上来就做大而全状态机框架，而是采用了一个较克制的做法：

- 保留现有 service 结构
- 新增统一生命周期协调层
- 先把关键入口收敛进去

这符合当前项目阶段“先闭环，再优化”的原则。

从 staged 代码看，至少已经集中出这些入口：

- `CreatePendingSubscription(...)`
- `CompleteFirstCharge(...)`
- `CancelSubscription(...)`
- `ExpireSubscription(...)`
- `ApplyRenewalSuccess(...)`
- `ApplyImmediateUpgrade(...)`
- `ScheduleDowngrade(...)`

这让后续 `WP-5 / WP-8 / WP-11` 有了更稳定的挂载点。

---

### 4.3 WP-1 / WP-2 已有修复成果被保留并收口进统一入口
这次修改没有破坏前两轮已经得到的成果，反而做了进一步收敛：

- `CreateSubscription()` 不再自己组装和驱动落库，而是转到 `CreatePendingSubscription(...)`
- `ChainService.ExecuteFirstCharge()` 不再自己组装激活成功后的对象更新，而是转到 `CompleteFirstCharge(...)`
- `SubscriptionManagementService` 不再自己改取消状态，而是转到 `CancelSubscription(...)`
- `RenewalService` 的过期 / 续费成功路径也已接到 lifecycle service
- `SubscriptionUpgradeService` 的升级 / 降级语义也开始统一入口

这说明当前实现不是“另起炉灶”，而是在延续修复主线。

---

### 4.4 `app.go` 依赖注入方向是正确的
`app.go` 中已经显式创建：

- `lifecycleService := service.NewSubscriptionLifecycleService(...)`

并注入到：

- `SubscriptionService`
- `ChainService`
- `SubscriptionManagementService`
- `RenewalService`
- `SubscriptionUpgradeService`

这使“统一入口”不仅存在于代码文件里，而且已经成为运行时依赖关系的一部分。

---

## 5. 高优先级问题

### P1-1：续费 / 升级相关链路虽然统一到了 lifecycle service，但仍然没有得到事务闭环

#### 现象
`SubscriptionLifecycleService` 中的以下方法：

- `ApplyRenewalSuccess(...)`
- `ApplyImmediateUpgrade(...)`
- `ScheduleDowngrade(...)`

虽然已经承担统一语义入口职责，但当前仍然是典型的**多步裸串行写入**，例如 `ApplyRenewalSuccess(...)` 中依次执行：

1. `charges.Create(...)`
2. `subscriptions.Update(...)`
3. `authorizations.Update(...)`
4. `events.Create(...)`

这些步骤之间没有像 `WP-1` 的 `CreateInitialState(...)`、`WP-2` 的 `CompleteFirstCharge(...)` 那样被事务收住。

#### 为什么这是问题
这说明当前实现完成的是：

> **统一入口**

而不是：

> **统一且可靠的状态闭环**

因此如果中途失败，仍可能留下：

- charge 已创建但 subscription 未更新
- subscription 已更新但 authorization 未扣减
- 状态已改但 event 未写入

#### 结论
这不是当前 `WP-3` 的阻断项，因为 `WP-3` 的核心目标是“收敛入口”，不是“一次性做完事务架构统一”。

但这必须被明确记账：

> **WP-3 把后续事务化改造的挂点收出来了，但没有消化掉 WP-8 的一致性问题。**

#### 建议修复
后续在 `WP-8` 优先把下列方法纳入一致事务策略：

- `ApplyRenewalSuccess(...)`
- `ApplyImmediateUpgrade(...)`
- `ScheduleDowngrade(...)`

至少做到：

- 生命周期语义继续保留在 lifecycle service
- 但多表写入改由统一事务方法承载

---

### P1-2：新引入的生命周期单点服务缺少直接测试，当前更多是“间接证明”

#### 现象
这次修改后，关键业务语义被集中到了：

- `domain/subscription.go`
- `subscription_lifecycle_service.go`

但当前 staged 测试里，直接可见的新增 / 修改测试主要仍集中在：

- `subscription_service_test.go`
- `chain_service_test.go`

这些测试能证明：

- 创建订阅会通过 lifecycle 入口
- 首次激活会通过 lifecycle 入口
- 首次激活前置状态校验仍然成立

但还没有看到对下面这些方法的直接语义测试：

- `CancelSubscription(...)`
- `ExpireSubscription(...)`
- `ApplyRenewalSuccess(...)`
- `ApplyImmediateUpgrade(...)`
- `ScheduleDowngrade(...)`
- `ErrInvalidSubscriptionTransition` 的 domain 级断言

#### 为什么这是问题
本轮把更多业务正确性压到了统一入口上；如果这个统一入口本身缺少直接测试，那么：

- 以后改动容易只保住“调用发生了”，却保不住“语义正确”
- 取消 / 过期 / 升级 / 降级这些路径的回归信心仍然偏弱

#### 结论
这不是当前拒绝验收 `WP-3` 的理由，但它是一个明显的测试缺口。

#### 建议修复
后续建议补一组直接面向 lifecycle service / domain 语义的测试，至少覆盖：

1. `pending -> active` 成功与非法激活
2. `active -> cancelled` 成功与非法取消
3. `active -> expired` 成功与非法过期
4. 续费成功时 charge / subscription / authorization / event 的最小一致性
5. 升级 / 降级入口的最小行为断言

---

## 6. 中优先级设计问题

### P2-1：Xray 仍然只是占位，没有被真正纳入生命周期统一入口

当前 event metadata 已统一补了：

- `lifecycle_action`
- `xray_sync_hook: "wp5_pending"`

这说明实现者已经明确意识到：

> 生命周期入口应该成为未来 Xray 同步的挂载点

这是对的。

但现阶段它仍然只是占位，并不代表生命周期闭环已经打通。

因此当前准确表述应该是：

> **WP-3 完成了“状态迁移入口统一”，但还没有完成“状态迁移驱动外部副作用统一”。**

后续应在 `WP-5` 中把这些占位替换成真实 Xray 同步语义。

---

### P2-2：部分依赖已经处于过渡态，后续可做小范围清理

从当前代码看，仍存在一些过渡态痕迹，例如：

- `ChainService` 仍保留 `events repository.EventRepository` 字段，但主成功路径已转向 lifecycle 入口
- `RenewalService` 仍持有 `chainService *ChainService`，但当前 `processRenewal(...)` 中未体现对其的实际使用

这些问题现在不会阻断 `WP-3`，但说明代码还处在“从分散实现迁移到统一入口”的中间态。

建议后续在不扩大任务边界的前提下做小范围清理，避免长期保留迷惑性依赖。

---

## 7. 测试审计评价

### 已覆盖的内容
当前 staged 结果至少已经证明：

- `go test ./...` 通过
- 首次激活仍然正确走 `pending -> active`
- 首次激活前置状态校验仍然成立
- 创建订阅路径已经切到 lifecycle 入口
- WP-1 / WP-2 原有修复没有被这次收敛破坏

### 仍缺的关键测试
建议后续补这些更贴近“统一入口自身正确性”的用例：

1. `Subscription.Activate / Cancel / Expire` 的 domain 单元测试
2. `CancelSubscription(...)` 成功 / 非法取消测试
3. `ExpireSubscription(...)` 成功 / 非法过期测试
4. `ApplyRenewalSuccess(...)` 中间失败语义测试
5. `ApplyImmediateUpgrade(...)` / `ScheduleDowngrade(...)` 最小行为测试

---

## 8. 与前次审计的关系

### 与 WP-1 的关系
这次修改延续了 `WP-1` 中“创建链路真实落库”的方向：

- 创建入口已进一步从具体 service 实现收敛到 lifecycle service
- 但 `WP-1` 中提到的“创建链路和其他关键写入路径的事务边界统一”仍未最终完成

### 与 WP-2 的关系
这次修改延续了 `WP-2` 中“首次激活成功路径事务化”的方向：

- `ChainService` 继续保留了按 ID 查询与前置状态校验
- 首次激活的最终状态更新收敛到 `CompleteFirstCharge(...)`

这说明 `WP-3` 没有回退 `WP-2` 的核心修复成果，这是明显正向结果。

---

## 9. 建议给后续 AI 的回修 / 设计顺序

### 本轮可以先接受为“WP-3 核心完成”
建议采用下面这个口径：

> 已将关键订阅生命周期状态迁移从多个 service 的分散实现，收敛为更明确的 domain 语义与 lifecycle service 统一入口；但续费 / 升级等链路仍未完成事务闭环，Xray 副作用也尚未接入，因此当前完成的是“状态机入口统一”，不是“完整生命周期闭环完成”。

### 下一轮优先工作建议
建议后续按这个顺序推进：

1. **WP-5：把统一生命周期入口真正接入 Xray 同步**
   - 不要再让 Xray 调用散落回各个 service
   - 直接以 lifecycle service 为挂载点

2. **WP-8：把续费 / 升级 / 降级等多表写入路径事务化**
   - 优先处理 `ApplyRenewalSuccess(...)`
   - 再看升级 / 降级的写入一致性

3. **补 lifecycle service / domain 的直接测试**
   - 让新的统一入口成为可回归的单点

4. **最后再考虑 context / repository transaction 统一**
   - 这属于 `WP-11` 范畴，不建议在当前阶段提前扩大范围

---

## 10. 最终审计结论

**结论一句话：**

> 这次 staged 修改已经实质性完成了 `WP-3` 最关键的目标：把创建、首次激活、取消、过期以及部分续费 / 升降级语义，从多个 service 的分散状态修改收敛到统一的 lifecycle 入口，并通过 domain 级最小状态迁移规则提升了语义清晰度；当前 `go test ./...` 也已通过。与此同时，它还没有把续费 / 升级链路变成事务可靠闭环，也尚未把 Xray 副作用真正接入，因此建议按“核心语义收敛完成、后续一致性与外部同步工作仍待继续”来验收，而不要把它表述成生命周期闭环已经全部完成。
