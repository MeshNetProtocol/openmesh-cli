# WP-1 Staged 代码审计报告（2026-04-24）

**审计对象**: 当前已 staged 的 `WP-1 创建订阅链路真实落库` 实现  
**审计日期**: 2026-04-24  
**审计结论**: **本报告已被后续修复部分消化；当前不再存在最初记录的 P0 阻断，但 WP-1 仍有未完全闭合的验收缺口，需要继续补齐。**

---

## 0. 后续修复状态更新（在 WP-2 完成后回写）

本报告最初记录的是 **WP-1 staged 状态**。在后续完成 `WP-2 首次激活链路修复` 后，相关遗留问题已有一部分被顺带消化，因此这里先更新当前状态，避免继续把已修复问题当作现状。

### 已修复
1. **原 P0-1 已修复**
   - `subscription_service_test.go` 的测试桩已经补齐：
     - `AuthorizationRepository.GetByID(...)`
     - `ChargeRepository.GetByID(...)`
   - 当前 `go test ./...` 已可通过，不再存在“WP-1 staged 代码无法通过最低验证命令”的阻断问题。

2. **创建链路与首次激活链路的事务组织方式已部分收口**
   - `WP-1` 的 `CreateInitialState(...)`
   - `WP-2` 的 `CompleteFirstCharge(...)`
   都收敛到了 `postgres.Store` 上的最小事务方法。
   这意味着本报告原来指出的“创建链路与首次激活链路事务风格分叉”风险已经**部分缓解**，虽然 repository / transaction 抽象层面仍未最终统一。

### 仍未修复 / 仍需注意
1. **“创建成功后可按 ID 读回完整数据”的验收口径仍未被专门测试证明**
   - 当前测试已经证明：
     - 创建链路会触发事务落库
     - 失败时会 rollback
   - 但还没有一条专门的真实读回验证，去证明：
     - subscription 可按 ID 读回
     - authorization 可按 ID / 明确查询路径读回
     - charge 可按 ID / 明确查询路径读回
     - 初始 event 可按现有查询语义读回

2. **service 仍然直接依赖 store 级事务能力**
   - 这不是当前的阻断项，但仍然是后续 `WP-8 / WP-11` 需要统一收口的设计债。

因此，**本报告后续章节中凡是把 P0-1 视为当前现状的内容，都应以上述更新为准。**

---

## 1. 审计范围

本次审计基于当前 staged diff，涉及文件：

- `market-blockchain/go.mod`
- `market-blockchain/internal/app/app.go`
- `market-blockchain/internal/service/subscription_service.go`
- `market-blockchain/internal/service/subscription_service_test.go`
- `market-blockchain/internal/store/postgres/postgres.go`
- `market-blockchain/internal/store/postgres/postgres_test.go`

同时对照了：

- `docs/V2_design/PHASE2_PHASE3_REMEDIATION_DEVELOPMENT_GUIDE.md` 中 `WP-1`
- 当前 repository / domain / handler / postgres 实现

---

## 2. 总体判断

这次 staged 修改**方向是对的**，已经开始把“创建订阅只组装对象、不真实落库”的问题往正确方向推进，具体体现在：

1. `CreateSubscription()` 不再只在内存里组装对象，而是尝试落库
2. 引入了 `CreateInitialState(...)`，把 `subscription / authorization / charge / event` 放进同一事务
3. 补了 `current_authorization_id`、`subscription_id`、`authorization_id` 等关键关联字段
4. 为事务成功 / 回滚补了 `sqlmock` 测试骨架

但是，**当前 staged 版本还不能判定为 WP-1 已完成**。主要原因不是“思路错误”，而是：

- 有**明确阻断问题**：`go test ./...` 当前失败
- 有**验收口径未被真正证明**：只验证了写入 SQL，没有验证“创建后可按 ID 查到”
- 有**设计层面的偏移**：service 直接依赖 store 级事务写入能力，绕过 repository / event repository，虽然短期可工作，但不利于后续 WP-3 / WP-8 / WP-11 收敛

---

## 3. 审计结论分级

### 结论
- **功能方向**：基本正确
- **当前可接受性**：**不可直接验收为完成**
- **建议状态**：`需要修正后再验收`

### 分级（按当前代码状态更新）
- **P0 / 阻断问题**：0 项（原 P0-1 已修复）
- **P1 / 高优先级缺口**：2 项
- **P2 / 设计改进项**：3 项

---

## 4. P0 阻断问题

### 当前状态

**原 P0-1 已修复。**

最初 staged 审计时，`go test ./...` 因测试桩缺少 `GetByID(...)` 方法而失败。该问题在后续修复中已经解决：

- `testAuthorizationRepo` 已补 `GetByID(id string)`
- `testChargeRepo` 已补 `GetByID(id string)`
- 当前项目最低验证命令可通过：

```bash
go test ./...
```

### 结论

当前这份审计报告**不再包含有效的 P0 阻断项**。后续关注点应转向：

- `P1-1`：补足“创建成功后可读回”的真实验证
- `P1-2`：后续继续收口事务抽象

---

## 5. P1 高优先级问题

### P1-1：当前测试只证明“执行了 INSERT”，没有证明“创建成功后可按 ID 读回”

#### 现状
这次补的测试主要分两类：

1. `subscription_service_test.go`
   - 验证 `CreateSubscription()` 会调用 `CreateInitialState(...)`
   - 验证持久化错误会向上返回

2. `postgres_test.go`
   - 验证事务内四次 INSERT
   - 验证中途失败会 rollback

#### 问题
这还没有覆盖 `WP-1` 文档里的两个关键验收口径：

- 创建接口调用成功后，DB 可查询到完整记录
- 后续按 ID 查询可以读到该订阅

换句话说，现在只证明“写语句发出去了”，**没有证明当前 schema / repository / 查询路径能把这批数据完整读回来**。

#### 风险
如果插入字段与 repository 的扫描字段、默认值、约束、列顺序、后续读取语义不一致，当前测试是发现不了的。

#### 建议修复
至少补一个真实仓储层集成测试或等价验证，覆盖：

1. 调用 `CreateSubscription()`
2. 再通过现有 repository 的 `GetByID(...)` / 相关查询方法读回
3. 校验：
   - subscription 存在
   - authorization 存在
   - charge 存在
   - 关键关联字段一致

---

### P1-2：`CreateSubscription()` 现在绕过 repository / event repository，后续统一事务边界会更难收敛

#### 现状
`SubscriptionService` 新增了：

```go
type subscriptionCreationStore interface {
    CreateInitialState(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error
}
```

然后在 service 内直接调用 `creator.CreateInitialState(...)`。

在 app 层实际注入的是 `postgres.Store`。

#### 问题
这意味着：

- service 原本依赖 repository 抽象
- 现在又额外依赖 store 级别的事务写入能力
- `event` 也不再通过 `EventRepository.Create(...)` 路径写入

这在短期内能完成事务落库，但中期会带来两个问题：

1. **事务边界与 repository 设计开始分叉**  
   后续 `WP-8`、`WP-11` 再想统一 repository context / transaction 模式时，会出现“有的地方走 repo，有的地方走 store 批量方法”的双轨结构。

2. **event 路径与现有代码风格不一致**  
   项目里其他 service 仍通过 `events.Create(...)` 处理事件，这里单独把 event 内嵌进 store 事务，未来会造成行为分裂。

#### 结论
这不是马上阻止合并的 P0，但它是一个**应回收的设计偏移**。

#### 建议修复
在 AI 完成 WP-2 后，建议回头做一次小范围设计收口，优先方案：

- 保留“单事务写入”的目标
- 但把事务能力收敛为更明确的事务抽象，而不是让单个 service 直接吃 `postgres.Store`
- 至少让“创建链路”和“首次激活链路”采用一致的事务组织方式

---

## 6. P2 设计改进项

### P2-1：`CreateInitialState(...)` 没有 context，和后续 WP-11 方向不一致

当前实现使用：

- `s.DB.Begin()`
- `tx.Exec(...)`

没有 `context.Context` 参与。

这与开发指南中的 `WP-11 repository context 设计统一` 方向不一致。虽然本次不是必须一步做到，但建议后续回收为：

- `BeginTx(ctx, ...)`
- `ExecContext(ctx, ...)`

否则后面做 shutdown / timeout / request cancel 传递时，这条链路还得返工。

---

### P2-2：事务写入没有检查 `RowsAffected`

当前 `UPDATE` / `INSERT` 路径只检查 error，不检查是否真的影响了预期记录数。

对于 `WP-1` 的新增 `INSERT` 问题不算特别严重，但既然 `postgres.Store` 已经开始承载事务关键路径，建议后续同类方法统一考虑：

- 对关键 `UPDATE` 检查 `RowsAffected == 1`
- 对需要强语义保证的写操作显式校验

这条更偏向后续 `WP-2` / `WP-8` 的一致性收口。

---

### P2-3：event 结构仍然只靠 metadata 关联 subscription，问题只是被延后了

这次 event metadata 中补了：

- `subscription_id`
- `authorization_id`
- `charge_record_id`
- `status`

这是有帮助的，但它仍然属于“把结构化关联信息放进 metadata 字符串”。

现有 `EventRepository.ListBySubscription(...)` 仍然靠：

```sql
WHERE metadata LIKE ...
```

所以这次修改**没有真正解决 event 审计结构弱的问题**，只是让创建事件比之前更可查。

这不属于 WP-1 必须完成项，但应明确记入后续：

- 这是 `WP-13` 要继续处理的设计债
- 不应因为这次 metadata 补强就误判为事件模型已经合理

---

## 7. 与 WP-1 验收标准逐项对照

### 验收项 1：创建接口调用成功后，DB 可查询到完整记录
- **当前判断**：**未被充分证明**
- **原因**：只有 mock / sqlmock 验证，没有读回验证

### 验收项 2：后续按 ID 查询可以读到该订阅
- **当前判断**：**未被验证**
- **原因**：缺少真实查询断言

### 验收项 3：任何中间失败都不会留下半成品数据
- **当前判断**：**部分证明**
- **原因**：sqlmock 已覆盖 rollback 逻辑，但还缺真实数据库层验证

### 补充判断
当前 staged 代码更接近：

> **已经把 WP-1 从“完全未实现”推进到“主实现已出现，但尚未达到可验收状态”。**

---

## 8. 建议给后续 AI 的处理顺序

考虑到当前状态已比 staged 审计时更靠前，建议按下面顺序继续：

### 先补 WP-1 剩余验收缺口
优先补：

1. **补“创建成功后可读回”的真实验证**
   - 重点不是再补 mock，而是证明当前 schema + repository 查询路径能把创建结果读回来。

2. **确认创建链路的读回口径完整**
   至少覆盖：
   - subscription 按 ID 可读
   - authorization 按 ID 可读
   - charge 按记录 ID 可读
   - event 至少按当前可用查询语义可定位

### 之后再做事务抽象收口
当创建链路和首次激活链路都已具备最小可信验证后，再处理：

- repository / transaction 抽象统一
- context 贯穿事务路径
- event 结构化关联字段

---

## 9. 建议回修任务单（给后续 AI）

### 回修目标
修复 `WP-1` 审计发现的剩余问题，使创建订阅链路达到可验收状态，并继续与 `WP-2` 的事务设计保持一致。

### 必做
1. 补“创建成功后按 ID 可读回”的验证
2. 确认创建结果的关键关联字段可以被现有 repository 正确读回
3. 确认创建链路与首次激活链路的事务组织方式继续保持一致

### 可延后但要记录
1. context 贯穿事务路径
2. event 结构化关联字段
3. repository / transaction 抽象统一

---

## 10. 最终审计结论

**结论一句话：**

> 这份报告最初记录的 staged 问题中，测试不通过这一阻断项已经在后续修复中被解决；但 `WP-1` 仍然缺少“创建成功后可按 ID 真实读回”的专门验证，且事务抽象仍停留在 store 级最小封装，因此现在更准确的结论是：**WP-1 已从“不可验收”推进到“接近可验收，但仍需补一项关键验证与保留若干设计债说明”。**
