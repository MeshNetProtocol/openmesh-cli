# CDP VPN 订阅支付 POC 测试执行手册

## 文档信息

**文档类型**: 测试执行手册  
**创建日期**: 2026-04-06  
**最后更新**: 2026-04-08  
**目标网络**: Base Sepolia  
**适用阶段**: 技术验证  
**状态**: 待执行

## 一、手册目的

本手册只回答一个问题:

**如何一步一步执行并完成 VPN 订阅扣费能力测试。**

本手册不再展开大段方案论证。方案背景、能力选型、架构判断请看:

- [cdp_subscription_payment_poc.md](./cdp_subscription_payment_poc.md)

本手册默认你已经有:

- Coinbase Developer Platform 开发者账号
- Base Sepolia 测试钱包
- 一个可修改的 Auth 服务代码库

## 二、本次测试要完成的结果

### 2.1 必须完成的验证项

1. **一次性订阅支付**
   - 为某个 `identity_address` 伪造一个订阅请求
   - 用另一个 Base Sepolia 钱包付款
   - Auth 服务确认支付并打印成功日志

2. **自动续费**
   - 为某个 `billing_account` 建立 Spend Permission
   - 通过命令或改数据触发一次续费
   - Auth 服务完成扣费并打印续费成功日志

3. **降低 ETH 门槛**
   - 至少记录一次“普通 EOA 是否需要 ETH”
   - 至少记录一次“Smart Account + Paymaster 是否可降低 ETH 要求”

### 2.2 本次测试的成功日志

#### 一次性支付成功

```text
[SUBSCRIPTION_ACTIVATED] order=ord_001 identity=0xIdentityAddr payer=0xPayerAddr amount=1.00 USDC network=base-sepolia tx=0xabc...
```

#### 自动续费成功

```text
[SUBSCRIPTION_RENEWED] identity=0xIdentityAddr billing_account=0xBillingSmartAccount amount=1.00 USDC period=weekly tx=0xdef...
```

## 三、测试范围

### 3.1 在范围内

- 伪造订阅请求
- Base Sepolia USDC 支付
- Auth 服务确认支付
- 记录 `identity_address` 与 `payer_address`
- 手动触发一次自动续费
- 记录 gas 门槛测试结果

### 3.2 不在范围内

- 真实 Xray 开通
- 真实 UUID 生成
- 正式前端页面
- 生产级数据库和监控
- 商户式 checkout / hosted payment link UI

## 四、测试前提

### 4.1 账户与地址角色

本次测试固定使用三类地址:

1. `identity_address`
   - 订阅绑定对象
   - 代表 VPN 客户端身份
   - 不要求持有支付资产

2. `payer_address`
   - 用于一次性支付
   - 可以与 `identity_address` 不同

3. `billing_account`
   - 用于自动续费
   - 建议使用支持 Spend Permissions 的 Smart Account

### 4.2 建议环境变量

```bash
export NETWORK=base-sepolia
export CDP_API_KEY_ID=...
export CDP_API_KEY_SECRET=...
export CDP_WALLET_SECRET=...
export X402_FACILITATOR_URL=https://api.cdp.coinbase.com/platform/v2/x402
export PAY_TO_ADDRESS=0xYourReceiverAddress
export SUBSCRIPTION_PRICE_USDC=1.00
export PLAN_ID=weekly_test
```

### 4.3 本地文件

在 POC 目录准备以下文件:

```text
subscription_requests.json
payments.json
auto_renew_profiles.json
```

推荐初始内容:

#### subscription_requests.json

```json
[]
```

#### payments.json

```json
[]
```

#### auto_renew_profiles.json

```json
[]
```

## 五、待开发的最小接口

本手册假设你会在 Auth 服务里补这几个最小接口或命令。

### 5.1 创建订阅请求

```http
POST /poc/subscriptions
```

请求体:

```json
{
  "identity_address": "0xIdentityAddr",
  "plan_id": "weekly_test"
}
```

响应示例:

```json
{
  "order_id": "ord_001",
  "identity_address": "0xIdentityAddr",
  "plan_id": "weekly_test",
  "amount": "1.00",
  "currency": "USDC",
  "network": "base-sepolia",
  "status": "pending"
}
```

### 5.2 x402 付费激活接口

```http
POST /poc/subscriptions/{order_id}/activate
```

行为要求:

1. 未支付返回 `402 Payment Required`
2. 支付成功后:
   - 读取 `payer_address`
   - 读取 `transaction_hash`
   - 把记录绑定到 `identity_address`
   - 打印成功日志

### 5.3 自动续费配置接口

```http
POST /poc/auto-renew/setup
```

请求体示例:

```json
{
  "identity_address": "0xIdentityAddr",
  "billing_account": "0xBillingSmartAccount",
  "spender_address": "0xAuthSpender",
  "permission_hash": "0xPermissionHash",
  "period_seconds": 604800
}
```

### 5.4 手动续费触发器

二选一即可:

#### HTTP 方式

```http
POST /poc/auto-renew/{identity_address}/trigger
```

#### CLI 方式

```bash
go run ./cmd/poc-renew --identity 0xIdentityAddr
```

## 六、执行顺序总览

按下面顺序做，不要跳步:

1. 准备测试钱包与测试资产
2. 在 Auth 服务实现最小接口
3. 跑一次一次性支付测试
4. 跑一次自动续费测试
5. 跑一次 gas 门槛对比测试
6. 汇总结果

## 七、步骤 1: 准备测试资产

### 7.1 准备付款钱包

- [ ] 准备一个 Base Sepolia EOA 钱包,记为 `payer_address`
- [ ] 从 CDP Faucet 领取 Base Sepolia USDC
- [ ] 从 Faucet 领取少量 Base Sepolia ETH

记录:

```text
payer_address=
usdc_balance=
eth_balance=
```

### 7.2 准备收款地址

- [ ] 准备一个 EVM 地址作为 `PAY_TO_ADDRESS`
- [ ] 确认该地址用于接收测试付款

记录:

```text
pay_to_address=
```

### 7.3 准备自动续费账户

推荐优先使用 Smart Account:

- [ ] 创建 `billing_account`
- [ ] 确认启用了 Spend Permissions
- [ ] 给该账户准备测试 USDC

记录:

```text
billing_account=
billing_usdc_balance=
```

## 八、步骤 2: 在 Auth 服务补最小功能

### 8.1 数据记录要求

Auth 服务至少要能写出以下记录。

#### 订阅请求记录

```json
{
  "order_id": "ord_001",
  "identity_address": "0xIdentityAddr",
  "plan_id": "weekly_test",
  "amount": "1.00",
  "currency": "USDC",
  "network": "base-sepolia",
  "status": "pending"
}
```

#### 支付记录

```json
{
  "order_id": "ord_001",
  "identity_address": "0xIdentityAddr",
  "payer_address": "0xPayerAddr",
  "plan_id": "weekly_test",
  "amount": "1.00",
  "currency": "USDC",
  "network": "base-sepolia",
  "payment_method": "x402",
  "transaction_hash": "0x...",
  "paid_at": "2026-04-08T10:03:11Z",
  "status": "confirmed"
}
```

### 8.2 x402 接口行为要求

`POST /poc/subscriptions/{order_id}/activate` 必须满足:

1. 接口未付款时返回 `402`
2. x402 支付成功后:
   - 验证支付金额
   - 验证网络
   - 提取 `payer_address`
   - 提取 `transaction_hash`
   - 更新订单状态为 `confirmed`
   - 打印激活日志

### 8.3 自动续费行为要求

触发续费时必须做:

1. 读取 `auto_renew_profiles.json`
2. 找到对应的 `permission_hash`
3. 发起一次 `useSpendPermission`
4. 成功后写续费记录
5. 打印续费日志

## 九、步骤 3: 执行一次性订阅支付测试

### 9.1 创建伪造订阅请求

请求:

```bash
curl -X POST http://localhost:8080/poc/subscriptions \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0xIdentityAddr",
    "plan_id": "weekly_test"
  }'
```

检查项:

- [ ] 返回 `order_id`
- [ ] `subscription_requests.json` 出现新记录

记录:

```text
order_id=
identity_address=
plan_id=
```

### 9.2 触发付费接口

使用付款钱包访问:

```text
POST /poc/subscriptions/{order_id}/activate
```

预期行为:

1. 第一次请求收到 `402 Payment Required`
2. x402 客户端完成支付
3. 请求自动重试
4. 服务端返回成功响应

### 9.3 成功验证

检查以下结果:

- [ ] 服务端打印 `SUBSCRIPTION_ACTIVATED`
- [ ] `payments.json` 新增记录
- [ ] 记录中 `identity_address != payer_address` 也能成功
- [ ] 有可追踪的 `transaction_hash`

建议记录模板:

```text
order_id=
identity_address=
payer_address=
transaction_hash=
amount=
result=PASS|FAIL
```

## 十、步骤 4: 执行自动续费测试

### 10.1 创建 Spend Permission

目标:

- spender: `0xAuthSpender`
- token: `usdc`
- allowance: `1.00 USDC`
- period: `7 天`

检查项:

- [ ] permission 创建成功
- [ ] 得到 `permission_hash`
- [ ] 将其写入 `auto_renew_profiles.json`

记录:

```text
billing_account=
spender_address=
permission_hash=
allowance=
period=
```

### 10.2 配置自动续费档案

请求示例:

```bash
curl -X POST http://localhost:8080/poc/auto-renew/setup \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0xIdentityAddr",
    "billing_account": "0xBillingSmartAccount",
    "spender_address": "0xAuthSpender",
    "permission_hash": "0xPermissionHash",
    "period_seconds": 604800
  }'
```

检查项:

- [ ] `auto_renew_profiles.json` 有记录
- [ ] profile 状态为 `active`

### 10.3 手动制造到期

任选一种:

1. 直接修改 `next_renew_at` 为过去时间
2. 提供测试命令强制跳过时间检查

记录:

```text
next_renew_at_before=
next_renew_at_after=
```

### 10.4 触发一次续费

CLI 示例:

```bash
go run ./cmd/poc-renew --identity 0xIdentityAddr
```

或 HTTP:

```bash
curl -X POST http://localhost:8080/poc/auto-renew/0xIdentityAddr/trigger
```

检查项:

- [ ] 发起扣费成功
- [ ] 返回或记录 `transaction_hash`
- [ ] 输出 `SUBSCRIPTION_RENEWED`

记录模板:

```text
identity_address=
billing_account=
permission_hash=
transaction_hash=
result=PASS|FAIL
```

## 十一、步骤 5: 执行 gas 门槛测试

### 11.1 测试 A: 普通 EOA

目标:

- 记录普通 EOA 路径下是否必须持有 ETH

检查:

- [ ] 若无 ETH 时支付是否失败
- [ ] 补入 ETH 后是否成功

记录:

```text
case=EOA
need_eth=yes|no
notes=
```

### 11.2 测试 B: Smart Account + Paymaster

目标:

- 验证 user operation 是否可被赞助

检查:

- [ ] 创建 spend permission 时启用 `useCdpPaymaster`
- [ ] 若无 ETH 仍可完成 user operation,记为成功

记录:

```text
case=SMART_ACCOUNT_PAYMASTER
need_eth=yes|no
notes=
```

### 11.3 测试 C: ERC20 Gas Payments

目标:

- 验证是否可通过 USDC 覆盖 gas

检查:

- [ ] 为 paymaster 提供 USDC allowance
- [ ] 执行一次 user operation

记录:

```text
case=ERC20_GAS_PAYMENT
need_eth=yes|no
notes=
```

## 十二、判定规则

### 12.1 一次性订阅测试通过

同时满足以下条件:

- [ ] 成功创建订单
- [ ] 成功完成 Base Sepolia USDC 支付
- [ ] 成功打印 `SUBSCRIPTION_ACTIVATED`
- [ ] 成功记录 `payer_address`
- [ ] 成功记录 `transaction_hash`

### 12.2 自动续费测试通过

同时满足以下条件:

- [ ] 成功创建 Spend Permission
- [ ] 成功触发一次 renew
- [ ] 成功打印 `SUBSCRIPTION_RENEWED`
- [ ] 能读取或确认本周期额度变化

### 12.3 Gas 门槛测试通过

满足以下任一即可:

- [ ] Smart Account + Paymaster 路径确认能降低 ETH 要求
- [ ] ERC20 gas payment 路径确认可行

## 十三、失败时排查

### 13.1 一次性支付失败

优先检查:

1. x402 facilitator URL 是否正确
2. 付款钱包是否有 Base Sepolia USDC
3. 付款钱包是否需要少量 ETH
4. 服务端金额、网络、收款地址配置是否正确
5. 服务端是否正确保存了订单状态

### 13.2 自动续费失败

优先检查:

1. billing account 是否在创建时启用了 Spend Permissions
2. `permission_hash` 是否正确
3. spender 地址是否与创建 permission 时一致
4. billing account 是否持有足够 USDC
5. 是否使用了正确 network

### 13.3 Gas 赞助失败

优先检查:

1. 是否使用 Smart Account 而不是普通 EOA
2. 是否显式开启 `useCdpPaymaster`
3. 是否在 Base 或 Base Sepolia
4. 若走 ERC20 gas payment,是否先做 allowance 授权

## 十四、测试结果模板

执行完成后,按以下格式填写:

### 14.1 一次性订阅

```text
identity_address=
payer_address=
order_id=
transaction_hash=
status=PASS|FAIL
notes=
```

### 14.2 自动续费

```text
identity_address=
billing_account=
permission_hash=
renew_transaction_hash=
status=PASS|FAIL
notes=
```

### 14.3 Gas 门槛

```text
EOA_need_eth=
SmartAccountPaymaster_need_eth=
ERC20GasPayment_need_eth=
recommended_path=
```

## 十五、推荐结论输出

测试结束后,建议最后只输出三类结论:

1. **一次性订阅支付是否可行**
2. **自动续费是否可行**
3. **当前最推荐的低门槛支付路径是什么**

## 十六、参考资料

- [cdp_subscription_payment_poc.md](./cdp_subscription_payment_poc.md)
- [项目总览](../0.项目总览.md)
- [技术方案](../1.技术方案.md)

---

**文档维护者**: [待填写]  
**状态**: 待执行
