# Phase 4 文件型 POC 验收清单

## 目标

本轮 Phase 4 只验证一件事：

**围绕 `VPNCreditVaultV4` 的最小链上职责，服务端是否可以独立完成订阅、续费、取消订阅、升级、降级的业务编排。**

当前阶段不引入数据库，不追求完整产品化，只验证技术方案是否成立。

---

## 验收范围

### 在范围内

- JSON 文件状态流转
- subscription / authorization / charge 三类对象
- `chargeId` 幂等
- 取消订阅后停止续费
- 升级立即补差价
- 降级下周期生效
- 调试接口与过期模拟接口

### 不在范围内

- 数据库
- 用户系统
- 权限控制
- 完整前端产品化
- 真正链上 permit 签名提交流程
- 多进程并发锁
- 财务级对账系统

---

## 验收前置条件

### 1. 服务可以启动

```bash
cd docs/V2_design/validation/phase4
./start.sh
```

### 2. 首页可访问

访问：

```text
http://localhost:8080/
```

应能看到 Phase 4 文件型订阅 POC 页面。

### 3. 调试接口可访问

```bash
curl http://localhost:8080/poc/debug/state
```

应能返回完整状态快照。

---

## 验收项 1：套餐加载正确

### 操作

```bash
curl http://localhost:8080/poc/plans
```

### 通过标准

- 返回 `plans`
- 至少包含：
  - `monthly-basic`
  - `quarterly-basic`
  - `yearly-pro`
- 每个 plan 都带有：
  - `plan_id`
  - `name`
  - `period_days`
  - `amount_usdc`
  - `allowance_periods`

### 失败判定

- 接口报错
- plans 为空
- 缺少基础套餐

---

## 验收项 2：创建订阅成功

### 操作

```bash
curl -X POST http://localhost:8080/poc/subscriptions \
  -H "Content-Type: application/json" \
  -d '{
    "identity_address": "0xaaaa000000000000000000000000000000000011",
    "payer_address": "0xbbbb000000000000000000000000000000000011",
    "plan_id": "monthly-basic"
  }'
```

### 通过标准

返回对象中应包含：

- `subscription_id`
- `identity_address`
- `payer_address`
- `plan_id = monthly-basic`
- `status = pending`
- `auto_renew = true`
- `amount_usdc = 1`
- `allowance_snapshot.target_allowance = 3`
- `allowance_snapshot.remaining_allowance = 3`

### 同时检查

`subscriptions.json` 中新增一条记录。

### 失败判定

- 未生成 `subscription_id`
- 状态不是 `pending`
- allowance 初始化错误

---

## 验收项 3：permit 授权记录成功

### 操作

```bash
curl -X POST http://localhost:8080/poc/authorizations/permit \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_xxx",
    "expected_allowance": 0,
    "target_allowance": 3,
    "permit_deadline_minutes": 30
  }'
```

### 通过标准

返回对象中应包含：

- `event_type = charge_authorized`
- `expected_allowance = 0`
- `target_allowance = 3`
- `status = confirmed`

### 同时检查

#### `authorizations.json`
新增一条授权记录。

#### `events.json`
新增：
- `identity_bound`
- `charge_authorized`

#### `subscriptions.json`
对应 subscription 的 allowance 快照被更新：

- `expected_allowance = 0`
- `target_allowance = 3`
- `remaining_allowance = 3`

### 失败判定

- 授权记录未写入
- allowance 快照未更新
- 事件未写入

---

## 验收项 4：首次扣费成功

### 操作

```bash
curl -X POST http://localhost:8080/poc/charges/initial \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_xxx"
  }'
```

### 通过标准

返回对象中应包含：

- `charge_id`
- `subscription_id`
- `charge_type = initial`
- `status = confirmed`
- `amount_usdc = 1`
- `tx_hash`

### 同时检查

#### `charges.json`
新增一条 `initial` charge。

#### `events.json`
新增一条 `identity_charged`。

#### `subscriptions.json`
对应订阅应更新为：

- `status = active`
- `last_charge_id = 当前 charge_id`
- `allowance_snapshot.remaining_allowance = 2`

### 失败判定

- 订阅未激活
- initial charge 未落盘
- allowance 未扣减

---

## 验收项 5：initial charge 幂等正确

### 操作

再次执行同样请求：

```bash
curl -X POST http://localhost:8080/poc/charges/initial \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_xxx"
  }'
```

### 通过标准

返回类似：

```json
{
  "success": true,
  "message": "charge already exists"
}
```

### 同时检查

- `charges.json` 不会新增第二条相同 initial charge

### 失败判定

- 又生成了新 initial charge
- 幂等返回不正确

---

## 验收项 6：取消订阅成功

### 操作

```bash
curl -X POST http://localhost:8080/poc/subscriptions/cancel \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_xxx"
  }'
```

### 通过标准

返回对象中：

- `status = cancelled`
- `auto_renew = false`

### 同时检查

`subscriptions.json` 中对应字段同步更新。

### 核心判断

取消订阅不修改任何链上状态，只修改服务端状态。

### 失败判定

- 没有变成 `cancelled`
- `auto_renew` 仍是 `true`

---

## 验收项 7：取消后不能继续续费

### 操作

```bash
curl -X POST http://localhost:8080/poc/charges/renew \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_xxx"
  }'
```

### 通过标准

返回错误：

```text
subscription auto renew disabled
```

### 核心判断

说明取消订阅后，服务端已停止后续 renewal 编排。

### 失败判定

- 取消后仍然能续费
- 又生成 renewal charge

---

## 验收项 8：升级成功并立即补差价

### 准备

先创建一个新的 `monthly-basic` 有效订阅。

### 操作

```bash
curl -X POST http://localhost:8080/poc/subscriptions/upgrade \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_upgrade_xxx",
    "plan_id": "yearly-pro"
  }'
```

### 通过标准

返回的 subscription 中：

- `plan_id = yearly-pro`
- `plan_name = Yearly Pro`
- `amount_usdc = 10`

### 同时检查

#### `charges.json`
新增一条：

- `charge_type = upgrade_proration`

#### 差价检查

从 `monthly-basic(1)` 升到 `yearly-pro(10)` 时：
- 差价应为 `9`

### 失败判定

- plan 没有切换
- 没生成 `upgrade_proration`
- 差价不正确

---

## 验收项 9：降级只登记，不立即生效

### 准备

先创建一个新的 `yearly-pro` 有效订阅。

### 操作

```bash
curl -X POST http://localhost:8080/poc/subscriptions/downgrade \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_downgrade_xxx",
    "plan_id": "monthly-basic"
  }'
```

### 通过标准

返回的 subscription 中应包含：

- `pending_plan_id = monthly-basic`
- `pending_plan_name = Monthly Basic`

并且当前仍保持：

- `plan_id = yearly-pro`

### 核心判断

说明降级只是在服务端登记为“下周期切换”。

### 失败判定

- 当前 plan 被立即改掉
- 没有 `pending_plan_id`

---

## 验收项 10：过期模拟接口可用

### 操作

```bash
curl -X POST http://localhost:8080/poc/test/expire \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_downgrade_xxx",
    "expired_hours_ago": 1
  }'
```

### 通过标准

返回：

- `success = true`
- `message = subscription expiry simulated`

### 同时检查

`subscriptions.json` 中：

- `current_period_end` 早于当前时间
- `current_period_start` 同步往前调整

### 失败判定

- 时间未修改
- 无法进入 renewal 测试

---

## 验收项 11：续费成功并推进账期

### 操作

在订阅被模拟过期后执行：

```bash
curl -X POST http://localhost:8080/poc/charges/renew \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_downgrade_xxx"
  }'
```

### 通过标准

返回对象中：

- `charge_type = renewal`
- `status = confirmed`

### 同时检查

#### `charges.json`
新增一条 renewal。

#### `subscriptions.json`
对应订阅应更新：

- `current_period_start` 推进
- `current_period_end` 推进
- `last_charge_id` 更新
- `allowance_snapshot.remaining_allowance` 扣减

### 失败判定

- renewal 未生成
- 账期未推进
- allowance 未变化

---

## 验收项 12：降级在 renewal 后正式生效

### 操作

对做过 downgrade + renew 的订阅查询：

```bash
curl -X POST http://localhost:8080/poc/subscriptions/query \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "sub_downgrade_xxx"
  }'
```

### 通过标准

renew 后应看到：

- `plan_id = monthly-basic`
- `plan_name = Monthly Basic`
- `pending_plan_id` 已清空
- `pending_plan_name` 已清空

### 核心判断

说明降级策略已由服务端成功控制，并在下一周期切换，无需链上订阅状态机。

### 失败判定

- renewal 后仍未切 plan
- `pending_plan_id` 未清空

---

## 验收项 13：调试接口完整可用

### 操作

```bash
curl http://localhost:8080/poc/debug/state
```

### 通过标准

返回结果中包含：

- `plans`
- `subscriptions`
- `authorizations`
- `charges`
- `events`

### 核心价值

该接口是当前文件型 POC 的统一观察窗口，必须可用。

### 失败判定

- 缺字段
- 返回错误
- 返回内容和实际文件状态不一致

---

## 最终通过标准

如果下面 8 条全部成立，则可以判定 Phase 4 文件型 POC 技术验证通过：

1. 订阅创建成功，服务端可保存订阅状态
2. permit 授权过程可正确记录 allowance 快照
3. 首次扣费能把 subscription 从 `pending` 推到 `active`
4. 相同 charge 不会被重复创建
5. 取消订阅只改服务端，不依赖链上取消逻辑
6. 升级可通过差价 charge 实现
7. 降级可通过“下周期切换”实现
8. 续费可在到期后推进账期，并应用待生效套餐变更

---

## 架构结论

如果本清单全部通过，可以得出以下结论：

### 结论 1
`VPNCreditVaultV4` 的职责边界是合理的。

### 结论 2
链上不需要保存订阅、取消、升级、降级状态。

### 结论 3
真正的订阅系统应在服务端，而不是合约里。

### 结论 4
未来把 JSON 文件替换成数据库，只是存储层升级，不是架构重做。

---

## 下一步建议

完成本清单后，推荐进入下一阶段：

1. 把 `web/subscribe.html` 改成适配新接口的最小测试页面
2. 增加真实 permit 签名与 relayer 调用适配层
3. 在确认模型稳定后，再把 JSON 文件切换成数据库
