# Phase 4 POC：文件型订阅服务重构方案

## 目标

本次 Phase 4 不再实现数据库版本的订阅中心，而是用 JSON 文件完成一个可以验证技术链路的 POC。

验证目标只有 4 个：

1. 首次订阅可跑通
2. 自动续费可跑通
3. 取消订阅可跑通
4. 升级/降级可跑通

链上合约继续使用 `VPNCreditVaultV4` 的职责边界：

- `authorizeChargeWithPermit(...)`：设置 allowance，并在首次授权时绑定 `identity -> payer`
- `charge(chargeId, identityAddress, amount)`：按唯一 `chargeId` 扣费
- `executedCharges[chargeId]`：防止重复扣费

服务端只负责业务编排，不负责保管资金。

---

## POC 设计原则

### 1. 不上数据库

当前阶段只验证：

- 订阅业务逻辑是否清晰
- 服务端是否能围绕最小化合约工作
- 订阅/续费/取消/升降级的状态流转是否可执行

所以全部状态落在 JSON 文件里。

### 2. 不在链上保存订阅状态

以下业务语义全部放到服务端：

- 是否订阅中
- 当前套餐
- 账期开始和结束
- 是否自动续费
- 是否取消
- 升级/降级什么时候生效
- 账单解释

链上只看：

- 是否授权
- 是否绑定 payer
- 某个 chargeId 是否已经扣过

### 3. 多服务器问题用“双层幂等”处理

第一层：服务端文件记录唯一 charge
第二层：链上 `chargeId` 去重

即使 POC 只有一个进程，也必须保留这个设计，因为它是未来扩展成正式版的核心。

---

## 文件型数据模型

本目录下新增 5 个 JSON 文件：

### `plans.json`
定义可选套餐。

### `subscriptions.json`
记录订阅当前状态，是服务端最核心的数据源。

### `authorizations.json`
记录一次 permit 授权请求及其 allowance 快照。

### `charges.json`
记录每一笔实际扣费任务。

### `events.json`
记录服务端视角下的链上结果镜像，用于调试和验证流程。

---

## 推荐状态结构

### 1. Subscription

```json
{
  "subscription_id": "sub_demo_monthly_001",
  "identity_address": "0x...",
  "payer_address": "0x...",
  "plan_id": "monthly-basic",
  "status": "active",
  "auto_renew": true,
  "amount_usdc": 1,
  "current_period_start": "2026-04-19T00:00:00Z",
  "current_period_end": "2026-05-19T00:00:00Z",
  "allowance_snapshot": {
    "expected_allowance": 0,
    "target_allowance": 3,
    "remaining_allowance": 2
  }
}
```

`status` 建议只保留：

- `pending`
- `active`
- `cancelled`
- `expired`

### 2. Charge

```json
{
  "charge_id": "charge_demo_initial_monthly_001",
  "subscription_id": "sub_demo_monthly_001",
  "identity_address": "0x...",
  "amount_usdc": 1,
  "charge_type": "initial",
  "status": "confirmed"
}
```

`charge_type` 建议先支持：

- `initial`
- `renewal`
- `upgrade_proration`
- `downgrade_switch`

### 3. Authorization

```json
{
  "event_id": "evt_auth_demo_001",
  "event_type": "charge_authorized",
  "identity_address": "0x...",
  "payer_address": "0x...",
  "expected_allowance": 0,
  "target_allowance": 3,
  "permit_deadline": "2026-04-19T01:00:00Z",
  "status": "confirmed"
}
```

---

## 服务端需要验证的 4 条业务链路

## 一、首次订阅

### 输入

- `identity_address`
- `payer_address`
- `plan_id`

### 服务端步骤

1. 读取 `plans.json`
2. 根据 plan 计算：
   - `amount_usdc`
   - `expected_allowance`
   - `target_allowance`
3. 发起 permit 签名
4. 调用合约 `authorizeChargeWithPermit(...)`
5. 成功后在 `subscriptions.json` 写入订阅
6. 创建一条 `charges.json` 记录
7. 调用 `charge(chargeId, identityAddress, amount)`
8. 记录 `events.json`

### 验证点

- identity 首次绑定成功
- allowance 设置成功
- 首次扣费成功
- 服务端订阅状态为 `active`

---

## 二、自动续费

### 触发条件

当 `current_period_end <= now` 且 `auto_renew = true`

### 服务端步骤

1. 扫描 `subscriptions.json`
2. 找到到期且允许续费的订阅
3. 生成唯一 `chargeId`
4. 检查 `charges.json` 里是否已存在该账期扣费
5. 调用 `charge(...)`
6. 成功后：
   - 新增 charge 记录
   - 推进 `current_period_start`
   - 推进 `current_period_end`
   - 扣减 `remaining_allowance`

### 验证点

- 同一账期不会重复扣款
- `chargeId` 唯一
- 续费后订阅继续为 `active`

---

## 三、取消订阅

### 取消的定义

取消订阅不改链上状态，不调用额外合约函数。

### 服务端步骤

1. 找到 `subscription_id`
2. 把 `auto_renew` 改成 `false`
3. 把 `status` 改成 `cancelled`
4. 保留当前账期到 `current_period_end`

### 验证点

- 当前账期内仍可使用服务
- 后续不再生成 renewal charge
- 不需要改动智能合约任何状态

---

## 四、升级 / 降级

POC 建议先做最简单的版本。

### 方案

- 当前周期不做复杂链上变更
- 在服务端更新下一周期应使用的 plan
- 如果要验证“立即升级”，就补一笔差价 charge

### 升级（建议 POC 采用）

1. 用户从低价 plan 升到高价 plan
2. 服务端计算差价
3. 创建 `charge_type = upgrade_proration`
4. 调用 `charge(...)`
5. 更新 `subscriptions.json` 的 `plan_id`

### 降级（建议 POC 采用）

1. 用户从高价 plan 降到低价 plan
2. 当前账期不退款
3. 只更新下一期 plan 配置
4. 到下一次 renewal 时使用新 plan 金额

### 验证点

- 升级时可成功扣差价
- 降级时不会多扣
- 订阅主体仍然由服务端维护

---

## chargeId 生成建议

链上不解释 `chargeId`，但服务端必须稳定生成。

建议先生成字符串幂等键：

```text
{subcription_id}:{period_start}:{period_end}:{charge_type}
```

再映射为链上 bytes32：

```text
keccak256(utf8(idempotency_key))
```

POC 阶段可以先：

- JSON 文件中保存原始字符串 `charge_id`
- 真正发链时再转 bytes32

这样更容易调试。

---

## 推荐实现拆分

POC 阶段不需要拆微服务，但建议在 `auth-service` 内保留以下逻辑边界：

### 1. Plan Loader
负责读取 `plans.json`

### 2. Subscription Store
负责读取和写入 `subscriptions.json`

### 3. Authorization Store
负责记录 permit 过程

### 4. Charge Store
负责：
- 写入 charge
- 检查 charge 是否已存在
- 防止重复创建

### 5. Billing Engine
负责：
- 生成 renewal charge
- 升级差价 charge
- 降级下周期切换

### 6. Chain Gateway
负责真正调用：
- `authorizeChargeWithPermit(...)`
- `charge(...)`

---

## POC API 建议

建议把现有接口逐步改造成下面这组更贴近 V4 的接口：

### 1. 创建订阅
`POST /poc/subscriptions`

请求：

```json
{
  "identity_address": "0x...",
  "payer_address": "0x...",
  "plan_id": "monthly-basic"
}
```

### 2. 提交授权
`POST /poc/authorizations/permit`

用于调用 `authorizeChargeWithPermit(...)`

### 3. 执行首次扣费
`POST /poc/charges/initial`

### 4. 触发续费
`POST /poc/charges/renew`

### 5. 取消订阅
`POST /poc/subscriptions/cancel`

### 6. 升级套餐
`POST /poc/subscriptions/upgrade`

### 7. 降级套餐
`POST /poc/subscriptions/downgrade`

### 8. 查询订阅
`POST /poc/subscriptions/query`

---

## 当前代码需要重构的方向

当前 `auth-service` 仍然带有旧 POC 痕迹：

- 还在围绕直接支付交易 hash 做激活
- 还保留了 `auto_renew_profiles` 这样的旧模型
- 逻辑更接近“支付页 + Spend Permission”，而不是 “permit + chargeId + relayer”

新的方向应该是：

- 去掉对旧 Spend Permission 心智模型的依赖
- 改为围绕 `VPNCreditVaultV4` 的两个核心动作组织后端：
  - authorize
  - charge
- 所有订阅业务状态都写入 JSON 文件

---

## POC 成功标准

只要下面 4 条都打通，这一轮 Phase 4 就算技术验证成立：

- 首次订阅：permit + bind + initial charge 成功
- 自动续费：到期后 renewal charge 成功
- 取消订阅：服务端停续费成功，链上无额外状态要求
- 升级/降级：服务端调整 plan 并正确执行差价或下周期切换

---

## 下一步建议

下一步不要先写数据库，而是先做这 3 件事：

1. 重写 `auth-service/main.go` 的数据结构
2. 用 JSON 文件替换旧的 `subscription_requests.json / payments.json / auto_renew_profiles.json`
3. 把 API 改成围绕 subscription / authorization / charge 三类对象

这样你可以先把 Phase 4 的技术闭环跑通，等确认模型正确，再升级成数据库版。
