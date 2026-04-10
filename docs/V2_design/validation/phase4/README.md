# CDP 订阅支付 POC - 简化版

基于 Spend Permission 的订阅支付验证，支持 MetaMask 首次支付和自动续费。

## 核心流程

1. **Mac 客户端**（shell 脚本模拟）→ 生成订阅 URL → 打开浏览器
2. **Web 页面** → 连接 MetaMask → 创建 Spend Permission
3. **首次支付** → 服务端立即执行第一次扣费 → 激活订阅
4. **自动续费** → 服务端定期执行 Spend Permission 扣费

## 快速开始

### 1. 启动 Auth 服务

```bash
cd auth-service
go run .
```

服务运行在 `http://localhost:8080`

### 2. 模拟 Mac 客户端

```bash
./mac_client_simulator.sh [identity_address]
```

这会：
- 生成带 `identity_address` 的订阅 URL
- 自动打开浏览器到订阅页面

### 3. 在浏览器中完成订阅

1. 点击"连接 MetaMask"
2. 在 MetaMask 中确认连接
3. 点击"授权并支付"
4. 在 MetaMask 中确认 Spend Permission 授权
5. 等待首次支付完成
6. 订阅激活成功

## 技术方案

### 使用 Spend Permission 而不是 x402

**原因**：
- 可以一次性完成首次支付 + 授权自动续费
- 不需要 x402 facilitator
- 流程更简单

**Spend Permission 特性**：
- 用户授权服务地址可以定期扣费（例如每月 1 USDC）
- 首次授权时就扣第一笔费用
- 后续到期时服务自动执行扣费

### 账户模型

- **identity_address**: VPN 用户身份（订阅绑定主体）
- **billing_account**: MetaMask 钱包地址（支付账户）
- **spender_address**: 服务钱包地址（被授权扣费）

### 数据流

```
Mac 客户端
  ↓ 生成 URL
Web 页面 (subscribe.html)
  ↓ 连接 MetaMask
  ↓ 创建 Spend Permission
Auth 服务
  ↓ 执行首次扣费
  ↓ 激活订阅
  ↓ 定期自动续费
```

## 项目结构

```
phase4/
├── auth-service/           # Go 后端服务
│   ├── main.go            # 主服务逻辑
│   ├── cdp_client.go      # CDP API 客户端
│   └── go.mod
├── web/                   # Web 前端
│   └── subscribe.html     # 订阅支付页面
├── mac_client_simulator.sh # Mac 客户端模拟器
├── .env                   # 环境配置
└── README.md
```

## 环境配置

编辑 `.env`:

```bash
# CDP API 配置
CDP_API_KEY_NAME=organizations/{org_id}/apiKeys/{key_id}
CDP_API_KEY_PRIVATE_KEY=-----BEGIN EC PRIVATE KEY-----\n...\n-----END EC PRIVATE KEY-----

# 服务配置
SERVICE_WALLET_ADDRESS=0xYourServiceWallet
USDC_CONTRACT_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
SUBSCRIPTION_PRICE_USDC=1.00
NETWORK=base-sepolia
```

## 下一步

完成基础验证后：
1. 集成真实的 CDP Spend Permission SDK
2. 实现真实的链上扣费
3. 实现自动续费定时任务

## API 接口

### POST /poc/subscriptions
创建订阅请求

**请求**:
```json
{
  "identity_address": "0x...",
  "plan_id": "monthly"
}
```

**响应**:
```json
{
  "order_id": "ord_001",
  "identity_address": "0x...",
  "plan_id": "monthly",
  "amount": "1.00",
  "currency": "USDC",
  "network": "base-sepolia",
  "status": "pending"
}
```

### POST /poc/subscriptions/query
查询订阅信息

**请求**:
```json
{
  "identity_address": "0x..."
}
```

**响应**:
```json
{
  "subscription": {
    "order_id": "ord_001",
    "identity_address": "0x...",
    "status": "active",
    ...
  },
  "payments": [...],
  "auto_renew": {...}
}
```

### POST /poc/subscriptions/cancel
取消订阅

**请求**:
```json
{
  "identity_address": "0x..."
}
```

**响应**:
```json
{
  "success": true,
  "message": "Subscription cancelled"
}
```

### POST /poc/auto-renew/setup
配置自动续费

### POST /poc/subscriptions/{order_id}/activate
激活订阅（执行首次扣费）

### POST /poc/auto-renew/{identity_address}/trigger
手动触发续费

## 测试

运行完整的订阅管理测试：

```bash
./test_subscription_management.sh [identity_address]
```

这会测试：
- 创建订阅
- 查询订阅信息
- 配置自动续费
- 取消订阅
- 验证取消状态

