# Phase 2 数据模型设计稿

基于 `docs/V2_design/validation/phase4/README.md` 和 `docs/V2_design/validation/phase4/subscription-service/*` 的已验证链路，冻结 V1 正式服务端在 `market-blockchain/` 中采用的数据模型。

> 目标：
> - 保留 `subscription + authorization + charge` 核心抽象
> - 将 `phase4` 的 JSON 状态管理升级为数据库模型
> - 不改变已验证通过的首次订阅、续费、取消订阅、升级 / 降级业务语义

---

## 1. 设计原则

- 套餐不在链上，由服务端维护
- 订阅状态不在链上，由服务端维护
- 授权与扣费结果需要可追踪、可审计
- `chargeId` 必须可唯一追踪，防止重复扣费
- 事件记录既要支持排障，也要支持订阅历史查询

---

## 2. 核心实体

### 2.1 plans

用途：服务端维护套餐配置，对应 `phase4` 中的套餐定义。

建议字段：

- `plan_id`
- `name`
- `description`
- `period_seconds`
- `amount_usdc_base_units`
- `amount_usdc_display`
- `authorization_periods`
- `total_authorization_amount`
- `active`
- `created_at`
- `updated_at`

说明：
- `plan_id` 作为业务主键
- `amount_usdc_base_units` 作为扣费与链上交互的真实金额
- `amount_usdc_display` 仅用于展示

### 2.2 subscriptions

用途：记录订阅当前状态，是服务端的核心主表。

建议字段：

- `id`
- `identity_address`
- `payer_address`
- `plan_id`
- `status`
- `auto_renew`
- `current_period_start`
- `current_period_end`
- `next_plan_id`
- `last_charge_id`
- `last_charge_at`
- `source`
- `created_at`
- `updated_at`

说明：
- `status` 取值：`pending / active / expired / cancelled`
- `next_plan_id` 用于降级下期生效
- `source` 用于标记首次订阅、续费、升级、降级来源

### 2.3 authorizations

用途：记录 permit 授权状态和剩余额度。

建议字段：

- `id`
- `identity_address`
- `payer_address`
- `plan_id`
- `expected_allowance`
- `target_allowance`
- `authorized_allowance`
- `remaining_allowance`
- `permit_status`
- `permit_tx_hash`
- `permit_deadline`
- `authorization_periods`
- `created_at`
- `updated_at`

说明：
- `permit_status` 取值：`pending / completed / failed`
- `remaining_allowance` 用于续费调度判断是否还能继续扣费

### 2.4 charges

用途：记录每次首次扣费、续费扣费、升级补差价扣费。

建议字段：

- `id`
- `charge_id`
- `identity_address`
- `payer_address`
- `plan_id`
- `amount`
- `status`
- `tx_hash`
- `reason`
- `created_at`
- `updated_at`

说明：
- `charge_id` 必须唯一
- `status` 取值：`pending / completed / failed`
- `reason` 用于区分首次订阅、续费、升级补差价等用途

### 2.5 events

用途：记录订阅历史事件，支持审计和问题排查。

建议字段：

- `id`
- `identity_address`
- `payer_address`
- `plan_id`
- `charge_id`
- `type`
- `description`
- `metadata`
- `created_at`

建议事件类型：
- `first_subscribe`
- `charge_success`
- `charge_failed`
- `expired`
- `reauthorize`
- `cancel`
- `upgrade`
- `downgrade`

说明：
- `metadata` 可存 JSON 字符串，用于保留额外上下文

---

## 3. 核心关系

- 一个 `plan` 可被多个订阅使用
- 一个 `subscription` 对应一个当前生效套餐，但可有 `next_plan_id`
- 一个 `subscription` 可对应多条 `charge`
- 一个 `subscription` 可对应多条 `event`
- 一个 `authorization` 主要围绕 `identity_address + plan_id` 追踪授权状态与额度

---

## 4. 状态流转

### 4.1 首次订阅

1. 读取 `plan`
2. 创建或更新 `authorization`
3. Permit 成功后更新 `permit_status=completed`
4. 创建首次 `charge`
5. 扣费成功后创建 / 更新 `subscription`
6. 写入 `event:first_subscribe` 与 `event:charge_success`

### 4.2 自动续费

1. 扫描到期且 `auto_renew=true` 的 `subscription`
2. 检查 `authorization.remaining_allowance`
3. 创建新的 `charge_id`
4. 记录续费 `charge`
5. 扣费成功后推进账期
6. 写入 `charge_success` 事件

### 4.3 取消订阅

1. 更新 `subscription.auto_renew=false`
2. 更新 `subscription.status=cancelled`
3. 当前账期保留到 `current_period_end`
4. 写入 `event:cancel`

### 4.4 升级 / 降级

- 升级：生成补差价 `charge`，成功后立即切换 `plan_id`
- 降级：更新 `next_plan_id`，在下一期切换生效

---

## 5. 与 phase4 验证实现的映射

### phase4 套餐配置

对应正式模型：`plans`

### phase4 permit-store 中的 permit 状态

对应正式模型：`authorizations`

### phase4 的 charge 扣费记录

对应正式模型：`charges`

### phase4 的订阅历史

对应正式模型：`events`

### phase4 运行态订阅状态

对应正式模型：`subscriptions`

---

## 6. 当前冻结结论

当前 Phase 2 数据模型先冻结为以下 5 个核心实体：

- `plans`
- `subscriptions`
- `authorizations`
- `charges`
- `events`

后续如需新增表，必须满足以下条件：

1. 是 V1 核心链路的必要组成
2. 无法通过现有 5 个核心实体表达
3. 不改变 `phase4` 已验证通过的业务抽象

---

## 7. PostgreSQL 初版落地

首版 migration 已落到：

- `market-blockchain/internal/store/migrations/0001_phase2_initial_schema.sql`

首版 repository 接口已落到：

- `market-blockchain/internal/repository/plan_repository.go`
- `market-blockchain/internal/repository/subscription_repository.go`
- `market-blockchain/internal/repository/authorization_repository.go`
- `market-blockchain/internal/repository/charge_repository.go`
- `market-blockchain/internal/repository/event_repository.go`

这意味着当前 Phase 2 已完成从“验证态 JSON 模型”到“正式服务端数据库模型草案”的第一步迁移。
