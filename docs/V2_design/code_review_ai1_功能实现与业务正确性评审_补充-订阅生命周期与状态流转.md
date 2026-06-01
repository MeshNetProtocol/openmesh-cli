# AI-1 追加评审：订阅生命周期闭环与业务正确性补充

**文档日期**: 2026-04-24  
**角色定位**: AI-1（功能实现与业务正确性评审）  
**说明**: 本文档为对 `docs/V2_design/code_review_ai1_功能实现与业务正确性评审.md` 的追加补充，重点聚焦订阅生命周期闭环、首次激活、续费、升级/降级、状态流转与 Xray 同步之间的真实业务关系。只做评审，不修改代码。

---

## 1. 补充结论

继续审查 `renewal_service.go`、`subscription_upgrade_service.go`、`chain_service.go`、`subscription_upgrade_handler.go` 后，可以明确：

当前问题不只是“创建订阅未落库”，而是**整个订阅生命周期都没有真正闭环**。

如果把链路拆成：

1. 创建订阅  
2. 首次扣费成功后激活  
3. 到期自动续费 / 扣费失败后过期  
4. 升级 / 降级  
5. 状态变化驱动 Xray 同步  

那么当前代码在 **2~5** 各阶段都存在明显断点，导致文档中“订阅生命周期管理已完成”的说法仍然不成立。

---

## 2. 功能符合性补充

### 2.1 首次扣费激活链路存在严重断裂

#### 问题 A：`ChainService.ExecuteFirstCharge()` 基本无法正确查到 authorization / charge
- **严重程度**：Critical
- **文件路径**：`market-blockchain/internal/service/chain_service.go`
- **相关函数 / 模块**：`ExecuteFirstCharge`

**问题说明**：
函数中这样查数据：

```go
authorization, err := s.authorizations.GetByIdentityAndPlan("", "")
...
charge, err := s.charges.GetByChargeID("")
```

也就是：
- 查 authorization 时传入空 identity / 空 plan
- 查 charge 时传入空 chargeID

然后再用返回对象的 ID 和输入参数比较：

```go
if authorization == nil || authorization.ID != input.AuthorizationID
if charge == nil || charge.ID != input.ChargeRecordID
```

**为什么是问题**：
这不是正常的精确查询路径，几乎等价于“查不到正确记录”。从业务语义上看，首次扣费成功后的激活逻辑依赖错误的查询方式，本身就不可靠。

**影响**：
- 首次扣费后可能无法正确完成激活
- `pending -> active` 这条核心状态转移链路不可信
- Phase 2 的“订阅状态管理核心能力”并未真正成立

**触发条件 / 复现思路**：
1. 调用创建订阅 API
2. 进入首次扣费逻辑
3. `ExecuteFirstCharge()` 在 authorization / charge 查询阶段即失败

**建议修复方向**：
- 提供按主键/ID 查询的方法：
  - `GetAuthorizationByID`
  - `GetChargeByID` 或 `GetChargeRecordByID`
- 不要用空字符串查询再做 ID 过滤

---

### 2.2 激活成功后不会同步到 Xray

#### 问题 B：首次扣费成功后虽然设置为 active，但没有触发 Xray AddUser
- **严重程度**：High
- **文件路径**：
  - `market-blockchain/internal/service/chain_service.go`
  - `market-blockchain/internal/service/xray_sync_service.go`
- **相关函数 / 模块**：`ExecuteFirstCharge`、`SyncSubscriptionToXray`

**问题说明**：
`ExecuteFirstCharge()` 成功后会：

```go
subscription.Status = domain.SubscriptionActive
```

并更新数据库，但没有调用任何 Xray 同步逻辑。

**为什么是问题**：
业务上“首次支付成功 → 获得 VPN 访问权限”是最关键闭环。当前即使 DB 状态变成 `active`，Xray 里也不会真正添加用户。

**影响**：
- `active` 状态不代表用户真的可访问 VPN
- DB 状态与访问控制脱节
- 文档中“根据订阅状态向 Xray 添加用户”不成立

**建议修复方向**：
- 激活成功后必须触发 `AddUser`
- 明确同步失败策略：回滚、补偿、重试或待同步标记

---

### 2.3 续费链路可以改 DB，但不是完整支付闭环

#### 问题 C：`RenewalService` 更新 period 和 allowance，但没有看到真实扣费闭环
- **严重程度**：High
- **文件路径**：`market-blockchain/internal/service/renewal_service.go`
- **相关函数 / 模块**：`ProcessRenewals`、`processRenewal`

**问题说明**：
当前续费逻辑会：
1. 读取可续费订阅
2. 检查 `RemainingAllowance`
3. 创建 charge 记录
4. 更新 subscription period
5. 扣减 authorization.RemainingAllowance
6. 写 event

但同时存在几个明显问题：
- 注入了 `chainService`，却没有真正使用它去执行链上 charge
- 逻辑更像“数据库内部扣账”，不是“真实续费支付”
- 续费成功 / 失败后没有接入 Xray 同步

**为什么是问题**：
如果链上才是真实扣费来源，那么当前续费逻辑只是“在数据库里模拟扣费”，不是业务闭环。

**影响**：
- subscription 周期可能被延长，但真实支付未发生
- charge 记录存在，但支付事实不一定存在
- 续费后的访问权限状态没有和 Xray 同步

**建议修复方向**：
- 明确续费是否必须走链上 charge
- 若链上是权威来源，则 period 延长必须依赖真实扣费成功
- 补齐续费成功/失败后的 Xray 状态处理

---

### 2.4 过期逻辑只改 DB，不移除 Xray 用户

#### 问题 D：allowance 不足导致 expired 时，没有执行 Xray RemoveUser
- **严重程度**：High
- **文件路径**：`market-blockchain/internal/service/renewal_service.go`
- **相关函数 / 模块**：`processRenewal`

**问题说明**：
当 allowance 不足时，代码会：

```go
sub.Status = domain.SubscriptionExpired
s.subscriptions.Update(sub)
s.events.Create(...)
return fmt.Errorf("insufficient allowance")
```

但没有调用 Xray 用户移除逻辑。

**为什么是问题**：
业务语义上，过期意味着访问权限终止。如果 Xray 用户未被移除，expired 用户可能继续访问 VPN。

**影响**：
- 状态和权限脱节
- 过期用户可能被错误放行
- 访问控制与计费边界失真

**建议修复方向**：
- 过期后必须同步执行 `RemoveUser`
- 或通过统一状态迁移入口封装 DB 更新 + Xray 同步

---

### 2.5 升级链路是“直接换 plan”，缺少支付与一致性闭环

#### 问题 E：升级订阅直接修改 `subscription.PlanID`，但没有真实支付闭环
- **严重程度**：High
- **文件路径**：`market-blockchain/internal/service/subscription_upgrade_service.go`
- **相关函数 / 模块**：`UpgradeSubscription`

**问题说明**：
当前升级逻辑：
1. 读取当前订阅、旧套餐、新套餐
2. 计算 prorated charge
3. 创建 charge 记录
4. 直接修改 `subscription.PlanID`
5. 写 event

存在问题：

**1）只有 charge 记录，没有看到真实支付执行**  
升级不应只是“记一条 charge”，应有真实支付确认，或至少明确待支付状态。

**2）没有事务边界**  
如果 charge 创建成功但 subscription 更新失败，会留下半完成状态。

**3）authorization 没有同步调整**  
升级后 plan 价格变化，但 authorization / allowance 是否仍然匹配，没有看到一致性处理。

**影响**：
- 升级可能只是“数据库看起来成功”
- 真实支付与订阅状态不一致
- 后续续费可能基于错误套餐继续执行

**建议修复方向**：
- 明确升级语义：立即支付立即生效，还是待支付确认后生效
- 给升级链路补事务
- 处理 authorization / charge / subscription 一致性

---

### 2.6 降级链路相对合理，但依赖未完成的续费主链路

#### 问题 F：降级只写 `PendingPlanID`，后续是否真正生效依赖续费链路
- **严重程度**：Medium
- **文件路径**：`market-blockchain/internal/service/subscription_upgrade_service.go`
- **相关函数 / 模块**：`DowngradeSubscription`

**问题说明**：
当前降级逻辑：
- 校验 active
- 校验新 plan 更便宜
- 设置 `subscription.PendingPlanID`
- 写 event

这与“期末生效”的业务语义基本一致。问题在于，真正应用降级是在 `renewal_service.go` 里：

```go
if sub.PendingPlanID != "" {
    targetPlanID = sub.PendingPlanID
}
```

**为什么是问题**：
- 降级是否真正落地，完全依赖续费链路成功执行
- 而续费链路本身目前并未形成完整支付闭环

**影响**：
- 降级只是“计划过”，不等于已可靠落地
- 业务闭环依赖一个尚未成立的主链路

**建议修复方向**：
- 明确降级在 period end 的执行确认机制
- 给续费 / 应用 pending plan 的链路补完整一致性保护

---

### 2.7 订阅状态机定义和实际落地不一致

#### 问题 G：状态枚举存在，但真实状态机没有被统一实现
- **严重程度**：High
- **文件路径**：
  - `market-blockchain/internal/domain/subscription.go`
  - `market-blockchain/internal/service/subscription_service.go`
  - `market-blockchain/internal/service/chain_service.go`
  - `market-blockchain/internal/service/subscription_management_service.go`
  - `market-blockchain/internal/service/renewal_service.go`
- **相关函数 / 模块**：状态流转整体

**问题说明**：
当前状态枚举有：
- `pending`
- `active`
- `expired`
- `cancelled`

但真实的状态修改分散在多个 service 中：
- 创建时写 `pending`
- 首次扣费后改 `active`
- 取消时改 `cancelled`
- allowance 不足时改 `expired`

**为什么是问题**：
缺少统一状态迁移入口，导致：
1. 状态变更副作用不一致
2. event / Xray / charge / authorization 的协同缺失
3. 各条路径下字段更新不统一

**影响**：
- 生命周期逻辑易分叉
- 某些路径只改 DB，不改外部系统
- 无法保证所有状态变化都形成闭环

**建议修复方向**：
- 统一封装关键状态迁移：
  - activate
  - cancel
  - expire
  - renew
- 每种状态变化明确：
  - DB 更新内容
  - event 内容
  - Xray 同步动作
  - 失败处理策略

---

### 2.8 升级/降级 API 把业务错误全部当成 500

#### 问题 H：handler 没有区分业务错误与系统错误
- **严重程度**：Medium
- **文件路径**：`market-blockchain/internal/api/handlers/subscription_upgrade_handler.go`
- **相关函数 / 模块**：`UpgradeSubscription`、`DowngradeSubscription`

**问题说明**：
service 里有很多明显的业务错误，比如：
- `subscription not found`
- `can only upgrade active subscriptions`
- `new plan not found`
- `new plan must be more expensive than current plan`

但 handler 无论什么错误都：

```go
respondError(w, http.StatusInternalServerError, err.Error())
```

**为什么是问题**：
很多并不是内部错误，而是用户输入或状态不满足前置条件。全部返回 500 会误导客户端和调用方。

**影响**：
- 客户端难以区分可修复业务错误与系统异常
- 调试和联调成本升高

**建议修复方向**：
- `not found` → 404
- 非法状态 / 非法套餐切换 → 400 或 409
- 仅内部异常返回 500

---

## 3. 对“订阅状态流转是否完整”的最终补充判断

### 当前确实存在的能力
- 有状态字段与基础状态枚举
- 创建时尝试设为 `pending`
- 首次扣费成功后尝试设为 `active`
- 取消时设为 `cancelled`
- allowance 不足时设为 `expired`
- upgrade / downgrade 有基础逻辑

### 但没有真正闭环的关键点
1. **创建不落库**
2. **首次激活链路本身查询逻辑不可靠**
3. **激活 / 取消 / 过期都没有接入 Xray 同步**
4. **续费更像 DB 内部记账，不是真实支付闭环**
5. **升级 / 降级缺少事务与一致性保障**
6. **状态机没有统一入口，副作用分散**

**最终判断**：
“订阅状态流转已完整实现”这一说法不成立。当前更准确的状态应是：

> **状态枚举和若干局部状态修改已存在，但订阅生命周期的真实业务闭环尚未完成。**

---

## 4. 补充优先级建议

### 必须立即修
1. 修复 `ChainService.ExecuteFirstCharge()` 的 authorization / charge 查询逻辑
2. 把激活 / 取消 / 过期接入 Xray 同步
3. 明确 renewal 是否真实执行扣费，而不是只改数据库
4. 给升级链路补事务与支付闭环

### 下一轮优先修
1. 统一状态机入口
2. 统一 DB / event / Xray 副作用处理
3. 修复 upgrade / downgrade handler 错误码语义
4. 补 lifecycle 相关测试：
   - `pending -> active`
   - `active -> cancelled`
   - `active -> expired`
   - renewal success / fail
   - upgrade / downgrade

---

## 5. 最终补充结论

在已有主评审结论基础上，可以进一步确认：

- 问题不只是“Phase 3 没完成”，而是 **Phase 2 的生命周期管理本身也没有真实闭环**。
- 当前代码更像“状态字段 + 服务骨架 + 局部状态修改”，而不是“完整可运行的订阅状态机”。
- 如果继续推进 Phase 4，而不先修复这些问题，会把客户端适配建立在不可靠的后端语义之上。

因此，按照业务真实性判断：

> **在 P0 问题清零前，不应继续推进 Phase 4。**
