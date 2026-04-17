# 最终智能合约技术方案

## 目标

这份文档给出**最终版智能合约设计方案**。

它不考虑兼容旧代码，不考虑旧前端，不考虑旧服务端的迁移成本，只考虑一件事：

**怎样设计一个足够简单、语义清晰、适合订阅业务的智能合约。**

设计原则完全按你的要求：

1. 合约只保存最关键的信息。
2. 订阅是否仍然有效，尽量通过关键事实推导，而不是通过复杂状态字段表达。
3. 尽量不删除数据。
4. 用户再次操作时，优先复用旧记录，只修改关键字段，例如到期时间、套餐、是否继续自动续费。
5. 扫描、重试、续费调度、套餐提醒、失败统计、运营状态判断，全部交给服务器处理。
6. 合约不维护“活跃订阅列表”、不维护“待清理状态”、不依赖定时器或补偿 finalize。

---

# 一、总设计思路

这个合约的职责应该极度收缩，只做下面几件事：

1. 创建订阅
2. 取消后续自动续费
3. 成功续费后延长到期时间
4. 修改当前套餐
5. 查询订阅信息

除此之外，合约不负责：

- 维护谁是“当前活跃列表”
- 自动判断谁该被轮询
- 到期后自动清理旧数据
- 保存流量统计
- 保存暂停服务状态
- 保存失败次数
- 保存待重试任务
- 保存后台展示状态

一句话：

**合约保存事实，服务器保存过程。**

---

# 二、最终链上数据模型

## 2.1 Subscription 结构

建议最终结构如下：

```solidity
struct Subscription {
    address identityAddress;
    address payerAddress;
    uint96 lockedPrice;
    uint256 planId;
    uint256 period;
    uint256 startedAt;
    uint256 expiresAt;
    uint256 renewedAt;
    bool autoRenewEnabled;
}
```

## 2.2 字段解释

### 1. `identityAddress`
VPN 身份地址。

这是订阅记录的主键。

### 2. `payerAddress`
付款地址。

用于：
- 验证谁有权取消订阅
- 续费时从谁扣款
- 验证签名

### 3. `lockedPrice`
当前订阅周期锁定价格。

用于：
- 自动续费时直接按当前锁定价格扣费
- 避免后续套餐价格变动影响当前订阅约定

### 4. `planId`
当前生效的套餐。

### 5. `period`
当前周期长度。

例如：
- 月付 30 天
- 年付 365 天
- 测试套餐 1800 秒

### 6. `startedAt`
当前这一段订阅开始时间。

用于查询和审计。

### 7. `expiresAt`
当前订阅到期时间。

这是最核心字段。

### 8. `renewedAt`
最近一次成功续费时间。

用于审计和服务端对账。

### 9. `autoRenewEnabled`
后续是否允许自动续费。

它只表示：
- 下个周期是否允许服务器继续扣款续费

它不表示：
- 当前周期是否有效
- 当前服务是否暂停

---

# 三、合约不再保存的内容

以下内容明确不进入最终合约：

## 3.1 不保存当前活跃订阅列表

不保存：
- `activeSubscriptions`
- `activeSubscriptionIndex`
- `getAllActiveSubscriptions()`
- `getActiveSubscriptionCount()`

原因：
- 这是派生数据
- 容易脏
- 服务端更适合维护

## 3.2 不保存待生效套餐变更

不保存：
- `nextPlanId`
- 待生效降级
- pending change
- cancel pending change

原因：
- 状态机会明显复杂化
- 当前阶段没必要上链

## 3.3 不保存流量统计和流量暂停状态

不保存：
- `trafficUsedDaily`
- `trafficUsedMonthly`
- `lastResetDaily`
- `lastResetMonthly`
- `isSuspended`

原因：
- 这是运营和统计逻辑
- 应该完全在服务端处理

## 3.4 不保存“过期清理状态”

不保存：
- finalize 标记
- force close 标记
- 清理完成标记

原因：
- 到期就是到期，不需要 delete 才成立
- 合约没有定时器
- 不应依赖清理动作保证正确性

---

# 四、订阅状态的最终判定规则

这个方案尽量不用额外状态字段表示当前状态。

大部分状态只靠关键事实判断。

## 4.1 当前是否仍然在订阅期内

```text
expiresAt > now
```

这就是唯一标准。

## 4.2 当前是否会继续自动续费

```text
autoRenewEnabled == true
```

## 4.3 当前是否属于“已取消但仍可使用”

```text
expiresAt > now && autoRenewEnabled == false
```

## 4.4 当前是否已过期

```text
expiresAt <= now
```

## 4.5 当前是否可以重新订阅

```text
expiresAt <= now
```

也就是说：
- 不看是否 delete
- 不看是否 finalize
- 不看活跃列表
- 不看 pending 状态
- 只看是否过期

---

# 五、最终支持的业务场景与流程

下面是最终要支持的 5 个核心场景。

---

## 5.1 首次订阅

### 业务目标
用户第一次购买一个套餐。

### 合约输入
- `user`
- `identityAddress`
- `planId`
- `isYearly` 或者直接传价格和周期来源
- 用户签名
- permit 签名

### 核心校验
1. `identityAddress != address(0)`
2. 套餐有效
3. 当前 identity 不存在有效订阅：

```solidity
require(subscriptions[identityAddress].expiresAt <= block.timestamp, "already subscribed");
```

4. 用户签名有效
5. permit / transferFrom 成功

### 链上写入
直接写入一条订阅记录：

```solidity
subscriptions[identityAddress] = Subscription({
    identityAddress: identityAddress,
    payerAddress: user,
    lockedPrice: currentPrice,
    planId: planId,
    period: currentPeriod,
    startedAt: block.timestamp,
    expiresAt: block.timestamp + currentPeriod,
    renewedAt: block.timestamp,
    autoRenewEnabled: true
});
```

### 结果
订阅立即生效。

---

## 5.2 取消订阅

### 业务目标
用户停止后续自动续费，但当前已支付周期继续有效。

### 合约输入
- `identityAddress`
- 用户签名，或用户自己发起

### 核心校验
1. 订阅存在：

```solidity
require(sub.expiresAt > 0, "not subscribed");
```

2. 调用者是付款地址，或者签名验证通过

3. 当前尚未取消：

```solidity
require(sub.autoRenewEnabled, "already cancelled");
```

### 链上写入
只做一件事：

```solidity
sub.autoRenewEnabled = false;
```

### 不做的事情
- 不删除记录
- 不修改 `expiresAt`
- 不修改 `planId`
- 不修改 `lockedPrice`
- 不清空 `payerAddress`

### 结果
- 当前周期继续有效
- 服务器之后不再自动续费

---

## 5.3 续订 / 自动续费

这里统一成一个语义：

**续费成功，就延长到期时间。**

无论是服务器自动续费，还是某种后台触发的续费，本质都一样。

### 业务目标
用户当前订阅到期后，由服务器代表用户完成续费。

### 核心校验
1. 订阅存在：

```solidity
require(sub.expiresAt > 0, "not subscribed");
```

2. 允许继续自动续费：

```solidity
require(sub.autoRenewEnabled, "auto renew disabled");
```

3. 当前已经达到续费时点：

```solidity
require(block.timestamp >= sub.expiresAt, "renewal not due");
```

如果你想加一个宽限期，可以加：

```solidity
require(block.timestamp <= sub.expiresAt + RENEWAL_GRACE_PERIOD, "renewal window passed");
```

### 扣款逻辑
- 从 `payerAddress` 扣 `lockedPrice`
- 扣款失败，直接 revert 或 emit 失败事件，不修改订阅时间

### 成功后的链上写入

```solidity
uint256 renewalBase = block.timestamp > sub.expiresAt ? block.timestamp : sub.expiresAt;
sub.renewedAt = block.timestamp;
sub.expiresAt = renewalBase + sub.period;
```

### 结果
续费成功后，到期时间顺延一个周期。

### 续费失败时的规则
这点非常重要：

**续费失败，不修改任何关键订阅事实。**

也就是说：
- `expiresAt` 不变
- `planId` 不变
- `autoRenewEnabled` 不变

后面是否重试，完全由服务器决定。

---

## 5.4 升级订阅

### 业务目标
用户当前订阅还没到期，想立即切到更高套餐，并补差价。

### 核心校验
1. 当前仍在订阅期：

```solidity
require(sub.expiresAt > block.timestamp, "subscription expired");
```

2. 新套餐存在且等级更高
3. 用户签名验证通过
4. 补差价扣款成功

### 链上写入
立即修改：

```solidity
sub.planId = newPlanId;
sub.lockedPrice = newPrice;
sub.period = newPeriod;
```

### 不修改
- `expiresAt` 不变
- `autoRenewEnabled` 不变
- `startedAt` 不变

### 结果
新套餐立即生效，但当前周期结束时间不变。

---

## 5.5 降级订阅

这里给出最终设计结论：

**不做链上的“待生效降级”。**

### 原因
链上待生效降级一定会引入：
- `nextPlanId`
- pending 状态
- cancel pending change
- 更复杂的测试矩阵

这和你的原则冲突。

### 最终方案
降级只支持两种业务方式中的一种，由服务器决定产品规则：

#### 方案 A，立即降级
用户发起降级时，立刻切换到新套餐。

链上写入：

```solidity
sub.planId = newPlanId;
sub.lockedPrice = newPrice;
sub.period = newPeriod;
```

`expiresAt` 保持不变。

这种方式最简单，但可能不符合常见商业习惯。

#### 方案 B，不做链上降级函数
用户如果要降级，则在下次重新订阅或续费前，由服务器引导选择新套餐。

也就是：
- 当前周期不动
- 当前链上套餐不动
- 到期后重新按新套餐订阅

### 最终建议
为了让合约最简单，建议采用：

**方案 B，不提供独立的链上降级函数。**

也就是说：
- 立即升级支持
- 降级不上链排队
- 用户在下一次订阅时选新套餐

这是最符合“少上链状态”的做法。

---

# 六、再次订阅 / 重新激活旧记录

这是整个方案的关键点之一。

## 6.1 目标
用户以前订阅过，后来：
- 取消了自动续费
- 到期了
- 或者服务器没续费成功导致过期

现在他想重新订阅。

## 6.2 最终规则
只要：

```text
expiresAt <= now
```

就允许再次订阅。

## 6.3 链上处理方式
**不删除旧记录，不新建并行记录，直接覆盖关键字段。**

也就是重新写入：
- `payerAddress`
- `planId`
- `lockedPrice`
- `period`
- `startedAt = now`
- `expiresAt = now + period`
- `renewedAt = now`
- `autoRenewEnabled = true`

## 6.4 结果
旧记录被复用，新的订阅周期开始。

这完全符合你的要求：

> 用户再次操作的时候只需要修改关键的信息就能继续使用旧数据，比如到期日期。

---

# 七、最终函数清单

## 7.1 必须保留的函数

### 1. `subscribe(...)`
职责：
- 首次订阅
- 过期后重新订阅

说明：
当前合约里可以继续沿用 `permitAndSubscribe` 的思路，但在新设计里，它本质就是统一的 `subscribe`。

### 2. `cancel(...)`
职责：
- 关闭自动续费

可分成：
- 用户自己调用版本
- relayer 代发版本

### 3. `renew(...)`
职责：
- 成功扣款后延长到期时间

### 4. `upgrade(...)`
职责：
- 立即升级套餐
- 补差价

### 5. `getSubscription(identityAddress)`
职责：
- 查询订阅记录

### 6. `getUserIdentities(user)`
可选保留。

如果你仍然想在链上按用户查询 identity，可以保留。
如果追求极简，也可以删掉，完全靠事件索引。

---

## 7.2 建议删除的函数

### 1. `finalizeExpired(...)`
删除。

### 2. `getAllActiveSubscriptions()`
删除。

### 3. `getActiveSubscriptionCount()`
删除。

### 4. `downgradeSubscription(...)`
删除。

### 5. `cancelPendingChange(...)`
删除。

### 6. `_applyPendingChange(...)`
删除。

### 7. 所有流量相关函数
删除。

---

# 八、事件设计

事件只保留最关键的业务事实。

## 8.1 保留的事件

### `SubscriptionCreated`
首次订阅或重新订阅都可以发这个事件。

### `SubscriptionRenewed`
续费成功。

### `SubscriptionCancelled`
用户关闭自动续费。

### `SubscriptionUpgraded`
立即升级成功。

### `RenewalFailed`
可选保留。

如果你希望链上留有失败痕迹，可以保留。
如果你希望更极简，也可以完全不写失败事件，把失败日志全部留给服务器。

## 8.2 删除的事件

删除：
- `SubscriptionExpired`
- `SubscriptionForceClosed`
- `PendingChangeCancelled`
- `PendingChangeApplied`
- 所有流量相关事件

---

# 九、服务器与合约的职责边界

这是最终方案里最重要的部分之一。

## 9.1 合约负责

合约只负责：
- 存订阅事实
- 验证签名
- 验证付款
- 执行状态修改

## 9.2 服务器负责

服务器负责：
- 发现哪些订阅快到期
- 何时发起自动续费
- 续费失败后是否重试
- 通知用户余额不足
- 判断前端展示状态
- 统计谁当前活跃
- 统计套餐分布
- 统计流量
- 风控判断
- 生成管理后台视图

## 9.3 前端展示推荐规则

### 当前可用
```text
expiresAt > now
```

### 已取消但当前仍可用
```text
expiresAt > now && autoRenewEnabled == false
```

### 将继续自动续费
```text
autoRenewEnabled == true
```

### 已过期
```text
expiresAt <= now
```

---

# 十、降级场景的最终建议

因为你特别要求把升级、降级场景都考虑清楚，这里单独给最终结论。

## 10.1 升级
支持链上立即升级。

原因：
- 逻辑简单
- 用户感知明确
- 容易扣差价

## 10.2 降级
**不建议做链上的“延迟生效降级”。**

最终建议：
- 不提供 pending downgrade
- 不引入 nextPlanId
- 不引入额外状态机

如果业务上必须支持降级，优先采用：

### 简化降级方案
提供一个立即降级函数，但：
- 不退款
- 不改到期时间
- 只改当前 planId / lockedPrice / period

这是最简单的链上降级方案。

但如果你从产品上接受“降级在下一次订阅时选择新套餐”，那合约里最好**直接不做降级函数**。

## 10.3 最终推荐
为了满足“尽量少上链逻辑”的原则：

- **升级支持**
- **降级不上链排队，不做 nextPlanId**
- **用户在下一次周期开始时重新选择套餐**

---

# 十一、最终设计总结

最终合约的本质应该非常简单：

## 11.1 链上只回答 5 个问题
1. 这个 identity 当前套餐是什么
2. 这个 identity 订阅到什么时候
3. 这个 identity 后续还会不会自动续费
4. 这个 identity 最近一次成功续费是什么时候
5. 这个 identity 的付款地址是谁

## 11.2 合约不再回答的问题
- 谁当前在活跃列表
- 谁需要后台轮询
- 谁暂停服务了
- 谁有待生效套餐切换
- 谁需要清理
- 谁续费失败了几次
- 谁流量超限了

这些全部留给服务器。

## 11.3 生命周期总规则

### 首次订阅
写入新周期，开启自动续费

### 取消订阅
只关闭自动续费，不改当前到期时间

### 续费成功
延长到期时间

### 续费失败
不改关键事实

### 升级订阅
立即改套餐，不改当前到期时间

### 降级订阅
不做链上延迟降级，尽量交给下次订阅时选择

### 重新订阅
不删旧记录，只覆盖关键字段并开启新周期

---

# 十二、最终推荐版本

如果让我按你的原则给出一个最干净的最终结论，就是：

## 合约保留
- `Subscription` 精简结构
- `subscribe`
- `cancel`
- `renew`
- `upgrade`
- `getSubscription`
- 可选 `getUserIdentities`

## 合约删除
- finalize
- active list
- pending downgrade / nextPlanId
- 流量统计
- 暂停状态
- 所有依赖后台补清理的机制

## 状态判断核心
- 是否有效，只看 `expiresAt`
- 是否继续自动续费，只看 `autoRenewEnabled`

这就是最终方案。
