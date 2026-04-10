# Phase 4 快速启动指南

## 前置准备

### 1. 准备 Base Sepolia 测试钱包

你已经有 MetaMask 钱包，需要确保：

- [ ] 切换到 Base Sepolia 测试网
- [ ] 记录你的钱包地址作为 `payer_address`

### 2. 领取测试资产

访问以下 Faucet 领取测试资产：

**Base Sepolia USDC**:
- CDP Faucet: https://portal.cdp.coinbase.com/products/faucet
- 或使用 Coinbase Wallet 内置 Faucet

**Base Sepolia ETH**:
- Base Sepolia Faucet: https://www.coinbase.com/faucets/base-sepolia-faucet
- 或 Alchemy Faucet: https://www.alchemy.com/faucets/base-sepolia

### 3. 配置环境变量

```bash
cd docs/V2_design/validation/phase4
cp .env.example .env
```

编辑 `.env` 文件，填入你的配置：

```bash
# CDP API 配置（如果需要真实 x402 集成）
CDP_API_KEY_ID=your_cdp_api_key_id
CDP_API_KEY_SECRET=your_cdp_api_key_secret

# 收款地址（可以使用你的 MetaMask 地址）
PAY_TO_ADDRESS=0xYourMetaMaskAddress

# 其他配置保持默认即可
```

## 启动服务

```bash
cd auth-service
go mod download
go run main.go
```

服务启动后访问: http://localhost:8080

## 测试流程

### 测试 1: 一次性订阅支付

#### 步骤 1: 创建订阅请求

```bash
curl -X POST http://localhost:8080/poc/subscriptions \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0x1234567890123456789012345678901234567890",
    "plan_id": "weekly_test"
  }'
```

记录返回的 `order_id`。

#### 步骤 2: 激活订阅

```bash
curl -X POST http://localhost:8080/poc/subscriptions/ord_001/activate
```

**预期结果**:
- 终端输出: `[SUBSCRIPTION_ACTIVATED]` 日志
- `payments.json` 新增支付记录
- 返回成功响应

### 测试 2: 自动续费

#### 步骤 1: 配置自动续费

```bash
curl -X POST http://localhost:8080/poc/auto-renew/setup \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0x1234567890123456789012345678901234567890",
    "billing_account": "0xBillingSmartAccount1234567890123456789012",
    "spender_address": "0xAuthSpender1234567890123456789012345678",
    "permission_hash": "0xPermissionHash123456789012345678901234567890",
    "period_seconds": 604800
  }'
```

#### 步骤 2: 触发续费

```bash
curl -X POST http://localhost:8080/poc/auto-renew/0x1234567890123456789012345678901234567890/trigger
```

**预期结果**:
- 终端输出: `[SUBSCRIPTION_RENEWED]` 日志
- `auto_renew_profiles.json` 更新 `next_renew_at`
- 返回成功响应

## 当前状态

⚠️ **POC 模拟模式**

当前代码处于 POC 验证阶段，使用模拟数据：

- ✅ 4 个最小接口已实现
- ✅ JSON 文件存储已实现
- ⚠️ x402 支付验证：使用模拟数据
- ⚠️ Spend Permission 扣费：使用模拟数据

## 下一步

### 集成真实 CDP 功能

1. **x402 集成**
   - 参考: https://docs.cdp.coinbase.com/x402/quickstart-for-sellers
   - 需要实现真实的支付验证逻辑

2. **Spend Permissions 集成**
   - 参考: https://docs.cdp.coinbase.com/embedded-wallets/evm-features/spend-permissions
   - 需要实现真实的扣费逻辑

3. **Smart Account + Paymaster**
   - 参考: https://docs.cdp.coinbase.com/paymaster/docs/welcome/
   - 测试降低 ETH 门槛

## 验收标准

参考 [coinbase_commerce_poc.md](../coinbase_commerce_poc.md) 第十二节。

## 故障排查

### 服务无法启动

```bash
# 检查端口占用
lsof -i :8080

# 检查 Go 环境
go version

# 重新下载依赖
cd auth-service
rm go.sum
go mod tidy
```

### JSON 文件权限问题

```bash
# 确保文件可写
chmod 644 *.json
```

## 参考文档

- [CDP 订阅支付 POC 方案说明](../cdp_subscription_payment_poc.md)
- [CDP 订阅支付 POC 执行手册](../coinbase_commerce_poc.md)
- [Phase 4 README](README.md)
