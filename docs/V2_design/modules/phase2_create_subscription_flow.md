# Phase 2 创建订阅主流程设计稿

基于 `docs/V2_design/validation/phase4/README.md` 中的首次订阅链路，以及 `market-blockchain/` 当前冻结的数据模型，定义正式服务端的创建订阅主流程。

---

## 1. 目标

创建订阅主流程的目标是：

1. 读取并校验套餐配置
2. 创建订阅主记录
3. 创建授权记录
4. 创建首次扣费记录
5. 为后续 permit 签名和首次链上扣费做好服务端状态准备

> 说明：当前阶段先冻结服务端主流程的数据编排，不在这里直接完成链上扣费执行。

---

## 2. 对应 phase4 验证链路

参考 `docs/V2_design/validation/phase4/README.md` 中“首次订阅”流程：

1. 用户选择套餐
2. 服务端计算 `expectedAllowance / targetAllowance`
3. 用户签 permit
4. 服务端调用 `authorizeChargeWithPermit(...)`
5. 服务端生成首次 `chargeId`
6. 服务端调用 `charge(...)`
7. 写入订阅、授权、扣费相关状态

正式实现中，当前先拆成两个阶段：

### 阶段 A：创建订阅上下文

在用户签 permit 前后，先准备好服务端需要的本地状态：
- `subscription`
- `authorization`
- `charge`

### 阶段 B：执行链上授权与首次扣费

在后续链上交互阶段：
- 更新授权状态
- 更新首次扣费状态
- 推进订阅状态到 `active`

---

## 3. 输入参数

建议创建订阅服务方法输入包括：

- `subscription_id`
- `authorization_id`
- `charge_record_id`
- `identity_address`
- `payer_address`
- `plan_id`
- `expected_allowance`
- `target_allowance`
- `permit_deadline`
- `initial_charge_id`
- `initial_charge_amount`（可为空，默认取套餐金额）

---

## 4. 服务端主流程

### 4.1 校验输入

- identity address 不能为空
- payer address 不能为空
- plan 必须存在且处于 active
- allowance 必须大于 0
- 同一 `identity_address + plan_id` 不应重复创建活动中的订阅

### 4.2 读取套餐

从 `plans` 中读取：
- `period_seconds`
- `amount_usdc_base_units`
- `authorization_periods`

### 4.3 生成本地记录

#### subscription

初始状态建议为：
- `status = pending`
- `auto_renew = true`
- `source = first_subscribe`
- `current_period_start = now`
- `current_period_end = now + plan.period_seconds`
- `last_charge_id = initial_charge_id`

#### authorization

初始状态建议为：
- `permit_status = pending`
- `authorized_allowance = 0`
- `remaining_allowance = target_allowance`
- `authorization_periods = plan.authorization_periods`

#### charge

初始状态建议为：
- `status = pending`
- `charge_id = initial_charge_id`
- `reason = first_subscribe`
- `amount = initial_charge_amount 或套餐金额`

### 4.4 返回创建结果

返回：
- 读取到的 `plan`
- 新建的 `subscription`
- 新建的 `authorization`
- 新建的 `charge`

用于后续：
- API 返回给调用方
- 进入 permit 签名与链上首次扣费流程

---

## 5. 当前冻结结论

当前创建订阅主流程先冻结为：

- **先构建本地状态，再执行链上授权与首次扣费**
- 本地状态核心由以下 3 个实体组成：
  - `subscriptions`
  - `authorizations`
  - `charges`
- 当前创建服务方法只负责：
  - 校验输入
  - 读取套餐
  - 构建并返回 3 个核心记录

---

## 6. 已落地代码位置

当前主流程骨架已落地到：

- `market-blockchain/internal/service/subscription_service.go`

后续需要继续补齐：

1. repository 落库实现
2. API 请求 / 响应结构
3. permit 状态更新逻辑
4. 首次扣费状态更新逻辑
5. 订阅状态从 `pending` 推进到 `active` 的编排逻辑
