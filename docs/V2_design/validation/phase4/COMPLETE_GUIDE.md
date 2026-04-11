# OpenMesh VPN 订阅服务 - 完整指南

**版本**: V3.3 (基于 EIP-712 + CDP Paymaster)  
**最后更新**: 2026-04-11  
**状态**: ✅ 核心功能已完成,可进行测试

---

## 📋 目录

1. [项目概述](#项目概述)
2. [技术架构](#技术架构)
3. [已部署资源](#已部署资源)
4. [快速开始](#快速开始)
5. [核心测试步骤](#核心测试步骤)
6. [API 文档](#api-文档)
7. [前端集成](#前端集成)
8. [自动续费机制](#自动续费机制)
9. [生产环境部署](#生产环境部署)
10. [故障排查](#故障排查)

---

## 项目概述

### 核心特性

- ✅ **0 ETH Gas**: 通过 CDP Paymaster 赞助所有链上交易
- ✅ **EIP-712 签名**: 用户链下签名,安全可验证
- ✅ **智能合约**: VPNSubscription.sol 部署在 Base Sepolia
- ✅ **自动续费**: 后台服务自动监控和执行续费
- ✅ **订阅管理**: 完整的订阅/取消/查询 API
- ✅ **前端示例**: 开箱即用的 Web 界面

### 技术栈

- **区块链**: Base Sepolia (测试网)
- **智能合约**: Solidity + Foundry
- **后端**: Node.js + Express + CDP SDK
- **前端**: HTML + JavaScript + ethers.js
- **支付代币**: USDC (ERC-20)
- **Gas 赞助**: Coinbase Developer Platform Paymaster

---

## 技术架构

### 整体流程

```
用户 (MetaMask)
  ↓ 1. EIP-712 签名 (SubscribeIntent) - 0 gas
  ↓ 2. ERC-2612 Permit 签名 (USDC 授权) - 0 gas
后端 API (Node.js + Express)
  ↓ 3. 验证签名
  ↓ 4. 调用 CDP Server Wallet
CDP Server Wallet
  ↓ 5. 调用智能合约 permitAndSubscribe()
CDP Paymaster
  ↓ 6. 赞助 gas (用户 0 ETH)
VPNSubscription 合约 (Base Sepolia)
  ↓ 7. 执行 USDC 转账
  ↓ 8. 创建订阅记录
  ↓ 9. 触发 SubscriptionCreated 事件
后端监听服务
  ↓ 10. 更新数据库
  ↓ 11. 添加到自动续费队列
```

### 核心组件

#### 1. 智能合约 (VPNSubscription.sol)

**功能**:
- `permitAndSubscribe()` - 创建订阅 (EIP-712 + Permit)
- `executeRenewal()` - 执行自动续费
- `cancelFor()` - 取消订阅 (EIP-712 签名)
- `finalizeExpired()` - 清理过期订阅

**事件**:
- `SubscriptionCreated` - 订阅创建
- `SubscriptionRenewed` - 订阅续费
- `SubscriptionCancelled` - 订阅取消
- `RenewalFailed` - 续费失败
- `SubscriptionExpired` - 订阅过期

#### 2. 后端服务 (subscription-service/)

**模块**:
- `index.js` - Express API 服务器
- `cdp-transaction.js` - CDP 交易发送模块
- `renewal-service.js` - 自动续费服务

**API 端点**:
- `GET /api/config` - 获取配置
- `POST /api/subscription/prepare` - 准备订阅签名
- `POST /api/subscription/subscribe` - 执行订阅
- `POST /api/subscription/cancel` - 取消订阅
- `GET /api/subscription/:address` - 查询订阅
- `GET /api/renewal/status` - 自动续费状态
- `POST /api/renewal/trigger` - 手动触发续费

#### 3. 前端示例 (frontend/)

**文件**:
- `index.html` - 订阅页面
- `app.js` - 前端逻辑 (钱包连接、签名、API 调用)

---

## 已部署资源

### 1. 智能合约

```
合约地址: 0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
网络: Base Sepolia
区块浏览器: https://sepolia.basescan.org/address/0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
```

**部署信息**:
- Gas 使用: 2,619,514
- 部署账户: 0x729e71ff357ccefAa31635931621531082A698f6
- USDC 地址: 0x036CbD53842c5426634e7929541eC2318f3dCF7e

### 2. CDP Server Wallet

```
Account Name: openmesh-vpn-1775870994810
Address: 0x8c145d6ae710531A13952337Bf2e8A31916963F3
Network: base-sepolia
```

**用途**: 作为 Relayer 地址,用于调用合约执行自动续费

### 3. CDP Paymaster

```
Endpoint: https://api.developer.coinbase.com/rpc/v1/base-sepolia/NEBYVp2cH4KnkATJnEQ5BD9G38vB0Mk4
```

**配置**:
- 合约白名单: VPNSubscription (0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2)
- 允许的函数: `permitAndSubscribe`, `executeRenewal`, `cancelFor`, `finalizeExpired`
- Gas Policy:
  - Global limit: $50 USD
  - Per user limit: $1 USD, 1000 operations, Monthly cycle

### 4. 订阅计划

| Plan ID | 名称 | 价格 | 周期 |
|---------|------|------|------|
| 1 | 月付套餐 | 5 USDC | 30 天 |
| 2 | 年付套餐 | 50 USDC | 365 天 |

---

## 快速开始

### 前置要求

1. **Node.js** >= 16.x
2. **MetaMask** 浏览器扩展
3. **Base Sepolia 测试网配置**:
   - RPC URL: `https://sepolia.base.org`
   - Chain ID: `84532`
   - 货币符号: ETH
   - 区块浏览器: `https://sepolia.basescan.org`

### 1. 获取测试 USDC

访问 [Circle Faucet](https://faucet.circle.com/):
1. 输入你的钱包地址
2. 选择 Base Sepolia 网络
3. 领取测试 USDC

### 2. 启动后端服务

```bash
cd docs/V2_design/validation/phase4/subscription-service
npm install
npm start
```

服务将在 `http://localhost:3000` 启动。

### 3. 启动前端

```bash
cd docs/V2_design/validation/phase4/frontend

# 使用 Python
python3 -m http.server 8080

# 或使用 Node.js
npx http-server -p 8080
```

访问 `http://localhost:8080`

---

## 核心测试步骤

### 测试 1: 完整订阅流程 (端到端)

**目标**: 验证用户从连接钱包到订阅成功的完整流程

**步骤**:

1. **启动服务**
   ```bash
   # 终端 1: 启动后端
   cd subscription-service && npm start
   
   # 终端 2: 启动前端
   cd frontend && python3 -m http.server 8080
   ```

2. **连接钱包**
   - 访问 `http://localhost:8080`
   - 点击"连接 MetaMask"
   - 在 MetaMask 中确认连接
   - 确认显示正确的钱包地址和 USDC 余额

3. **创建订阅**
   - 选择"月付套餐 - 5 USDC"
   - 输入 VPN 身份地址 (可以使用你的钱包地址)
   - 点击"订阅 (0 ETH Gas)"

4. **签名确认**
   - **第一次签名**: EIP-712 SubscribeIntent (链下签名,0 gas)
   - **第二次签名**: USDC Permit 授权 (链下签名,0 gas)
   - 等待交易确认 (约 2-5 秒)

5. **验证结果**
   - 页面显示"订阅成功"
   - USDC 余额减少 5 USDC
   - 订阅状态显示"✅ 活跃"
   - 显示到期时间 (30 天后)

**预期结果**:
- ✅ 两次签名都成功
- ✅ 交易在链上确认
- ✅ 用户未支付任何 ETH (gas 由 Paymaster 赞助)
- ✅ 订阅状态正确显示

---

### 测试 2: 查询订阅状态

**目标**: 验证订阅查询 API

**步骤**:

```bash
# 替换为你的钱包地址
USER_ADDRESS="0x729e71ff357ccefAa31635931621531082A698f6"

curl http://localhost:3000/api/subscription/$USER_ADDRESS | jq
```

**预期输出**:
```json
{
  "subscription": {
    "userAddress": "0x729e71ff357ccefAa31635931621531082A698f6",
    "identityAddress": "0x...",
    "planId": 1,
    "expiresAt": 1744627200,
    "isActive": true,
    "isCancelled": false
  }
}
```

---

### 测试 3: 自动续费服务

**目标**: 验证自动续费监控和执行

**步骤**:

1. **查看自动续费状态**
   ```bash
   curl http://localhost:3000/api/renewal/status | jq
   ```

   **预期输出**:
   ```json
   {
     "checkIntervalSeconds": 60,
     "precheckHours": 24,
     "maxRenewalFails": 3,
     "subscriptionCount": 1,
     "subscriptions": [
       {
         "userAddress": "0x729e71ff357ccefAa31635931621531082A698f6",
         "expiresAt": 1744627200,
         "failCount": 0
       }
     ]
   }
   ```

2. **手动触发续费检查** (用于测试)
   ```bash
   curl -X POST http://localhost:3000/api/renewal/trigger
   ```

3. **查看后端日志**
   ```
   [Renewal] Checking 1 subscriptions...
   [Renewal] User 0x729e... expires in 29.5 days - OK
   ```

**预期结果**:
- ✅ 自动续费服务正常运行
- ✅ 定期检查订阅状态 (每 60 秒)
- ✅ 到期前 24 小时预检余额
- ✅ 到期后自动执行续费

---

### 测试 4: 取消订阅

**目标**: 验证用户取消订阅流程

**步骤**:

1. **在前端点击"取消订阅"**
   - 确认取消对话框
   - 在 MetaMask 中签名 (EIP-712 CancelIntent)
   - 等待交易确认

2. **验证结果**
   - 页面显示"取消成功"
   - 订阅状态显示"❌ 已取消"
   - 到期时间不变 (仍可使用到到期)

3. **查询订阅状态**
   ```bash
   curl http://localhost:3000/api/subscription/$USER_ADDRESS | jq
   ```

   **预期输出**:
   ```json
   {
     "subscription": {
       "isActive": true,
       "isCancelled": true
     }
   }
   ```

**预期结果**:
- ✅ 取消签名成功
- ✅ 订阅标记为已取消
- ✅ 用户仍可使用到到期时间
- ✅ 不会再自动续费

---

### 测试 5: CDP Paymaster Gas 赞助验证

**目标**: 确认所有交易都由 Paymaster 赞助,用户无需 ETH

**步骤**:

1. **记录用户 ETH 余额**
   ```bash
   cast balance $USER_ADDRESS --rpc-url https://sepolia.base.org
   ```

2. **执行订阅操作** (按测试 1 步骤)

3. **再次查询 ETH 余额**
   ```bash
   cast balance $USER_ADDRESS --rpc-url https://sepolia.base.org
   ```

4. **在区块浏览器查看交易**
   - 访问 `https://sepolia.basescan.org/address/$USER_ADDRESS`
   - 查看最新的 `permitAndSubscribe` 交易
   - 确认 Gas Fee 为 0 ETH

**预期结果**:
- ✅ 用户 ETH 余额完全不变
- ✅ 交易的 Gas Fee 显示为 0
- ✅ 交易由 CDP Paymaster 赞助

---

## API 文档

### 1. 获取配置

```http
GET /api/config
```

**响应**:
```json
{
  "contractAddress": "0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2",
  "usdcAddress": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
  "chainId": 84532,
  "network": "base-sepolia"
}
```

---

### 2. 准备订阅签名

```http
POST /api/subscription/prepare
Content-Type: application/json

{
  "userAddress": "0x...",
  "planId": 1,
  "identityAddress": "0x..."
}
```

**响应**:
```json
{
  "domain": {
    "name": "VPNSubscription",
    "version": "1",
    "chainId": 84532,
    "verifyingContract": "0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2"
  },
  "types": {
    "SubscribeIntent": [
      { "name": "user", "type": "address" },
      { "name": "planId", "type": "uint256" },
      { "name": "identityAddress", "type": "address" },
      { "name": "nonce", "type": "uint256" }
    ]
  },
  "value": {
    "user": "0x...",
    "planId": 1,
    "identityAddress": "0x...",
    "nonce": 0
  }
}
```

---

### 3. 执行订阅

```http
POST /api/subscription/subscribe
Content-Type: application/json

{
  "userAddress": "0x...",
  "planId": 1,
  "identityAddress": "0x...",
  "signature": "0x..."
}
```

**响应**:
```json
{
  "success": true,
  "txHash": "0x...",
  "subscription": {
    "userAddress": "0x...",
    "planId": 1,
    "expiresAt": 1744627200
  }
}
```

---

### 4. 查询订阅

```http
GET /api/subscription/:address
```

**响应**:
```json
{
  "subscription": {
    "userAddress": "0x...",
    "identityAddress": "0x...",
    "planId": 1,
    "expiresAt": 1744627200,
    "isActive": true,
    "isCancelled": false
  }
}
```

---

### 5. 取消订阅

```http
POST /api/subscription/cancel
Content-Type: application/json

{
  "userAddress": "0x...",
  "signature": "0x..."
}
```

**响应**:
```json
{
  "success": true,
  "txHash": "0x..."
}
```

---

### 6. 自动续费状态

```http
GET /api/renewal/status
```

**响应**:
```json
{
  "checkIntervalSeconds": 60,
  "precheckHours": 24,
  "maxRenewalFails": 3,
  "subscriptionCount": 1,
  "subscriptions": [...]
}
```

---

## 前端集成

### 安装依赖

```html
<script src="https://cdn.ethers.io/lib/ethers-5.7.2.umd.min.js"></script>
```

### 连接钱包

```javascript
const provider = new ethers.providers.Web3Provider(window.ethereum);
await provider.send('eth_requestAccounts', []);
const signer = provider.getSigner();
const userAddress = await signer.getAddress();
```

### EIP-712 签名

```javascript
// 1. 获取签名数据
const response = await fetch('http://localhost:3000/api/subscription/prepare', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ userAddress, planId, identityAddress })
});

const { domain, types, value } = await response.json();

// 2. 用户签名
const signature = await signer._signTypedData(domain, types, value);

// 3. 提交订阅
await fetch('http://localhost:3000/api/subscription/subscribe', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ userAddress, planId, identityAddress, signature })
});
```

---

## 自动续费机制

### 工作流程

1. **定期检查** (每 60 秒)
   - 查询所有活跃订阅
   - 检查到期时间

2. **预检阶段** (到期前 24 小时)
   - 检查用户 USDC 余额
   - 检查 USDC 授权额度
   - 余额不足时发送提醒 (TODO)

3. **续费阶段** (到期后)
   - 调用 `executeRenewal(user)`
   - 通过 CDP Paymaster 赞助 gas
   - 成功: 重置 failCount
   - 失败: failCount++

4. **强制停服** (failCount >= 3)
   - 调用 `finalizeExpired(user, true)`
   - 释放链上状态
   - 从监控列表移除

### 配置参数

在 `.env` 中配置:

```bash
RENEWAL_CHECK_INTERVAL_SECONDS=60  # 检查间隔 (秒)
RENEWAL_PRECHECK_HOURS=24          # 预检时间 (小时)
MAX_RENEWAL_FAILS=3                # 最大失败次数
```

---

## 生产环境部署

### 1. 环境变量配置

创建 `.env` 文件:

```bash
# CDP 配置
CDP_API_KEY_ID=your_api_key_id
CDP_API_KEY_SECRET=your_api_key_secret
CDP_WALLET_SECRET=your_wallet_secret
CDP_SERVER_WALLET_ACCOUNT_NAME=your_account_name
CDP_SERVER_WALLET_ADDRESS=0x...
CDP_PAYMASTER_ENDPOINT=https://api.developer.coinbase.com/rpc/v1/base/...

# 合约配置
VPN_SUBSCRIPTION_CONTRACT=0x...
USDC_CONTRACT=0x...

# 服务配置
PORT=3000
NODE_ENV=production

# 自动续费配置
RENEWAL_CHECK_INTERVAL_SECONDS=3600  # 生产环境建议 1 小时
RENEWAL_PRECHECK_HOURS=24
MAX_RENEWAL_FAILS=3
```

### 2. 数据库迁移

当前使用内存存储,生产环境建议使用:
- PostgreSQL (推荐)
- SQLite (轻量级)

**Schema 设计**:
```sql
CREATE TABLE subscriptions (
  user_address VARCHAR(42) PRIMARY KEY,
  identity_address VARCHAR(42) UNIQUE NOT NULL,
  plan_id INTEGER NOT NULL,
  expires_at BIGINT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  is_cancelled BOOLEAN DEFAULT false,
  fail_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_expires_at ON subscriptions(expires_at);
CREATE INDEX idx_identity ON subscriptions(identity_address);
```

### 3. 部署到主网

**Base Mainnet 配置**:
```bash
# 网络配置
NETWORK=base-mainnet
RPC_URL=https://mainnet.base.org
CHAIN_ID=8453

# USDC 地址 (Base Mainnet)
USDC_CONTRACT=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

**部署步骤**:
1. 部署 VPNSubscription 合约到 Base Mainnet
2. 配置 CDP Paymaster (主网 endpoint)
3. 更新环境变量
4. 启动服务

### 4. 监控和告警

**推荐工具**:
- **日志**: Winston / Pino
- **监控**: Prometheus + Grafana
- **告警**: PagerDuty / Slack

**关键指标**:
- 订阅成功率
- 续费成功率
- Paymaster 余额
- API 响应时间
- 失败订阅数量

---

## 故障排查

### 问题 1: MetaMask 连接失败

**症状**: 点击"连接 MetaMask"无响应

**解决方案**:
1. 确认已安装 MetaMask 扩展
2. 确认已切换到 Base Sepolia 网络
3. 刷新页面重试

---

### 问题 2: 签名失败

**症状**: MetaMask 弹窗显示错误

**解决方案**:
1. 检查 nonce 是否正确
2. 确认合约地址正确
3. 查看浏览器控制台错误信息

---

### 问题 3: 交易失败

**症状**: 签名成功但交易未确认

**可能原因**:
1. USDC 余额不足
2. USDC 授权额度不足
3. Paymaster 配置错误
4. 合约调用失败

**解决方案**:
```bash
# 1. 检查 USDC 余额
cast call $USDC_CONTRACT "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url https://sepolia.base.org

# 2. 检查授权额度
cast call $USDC_CONTRACT "allowance(address,address)(uint256)" $USER_ADDRESS $CONTRACT_ADDRESS --rpc-url https://sepolia.base.org

# 3. 查看交易详情
cast tx $TX_HASH --rpc-url https://sepolia.base.org
```

---

### 问题 4: 自动续费不工作

**症状**: 订阅到期但未自动续费

**解决方案**:
1. 检查后端服务是否运行
2. 查看自动续费状态: `curl http://localhost:3000/api/renewal/status`
3. 检查订阅是否在监控列表中
4. 查看后端日志

---

### 问题 5: Paymaster Gas 未赞助

**症状**: 用户被要求支付 ETH

**解决方案**:
1. 检查 Paymaster 配置
2. 确认合约在白名单中
3. 确认函数在允许列表中
4. 检查 Gas Policy 限额

---

## 参考资料

- [VPNSubscription 合约源码](../contracts/src/VPNSubscription.sol)
- [CDP Server Wallets 文档](https://docs.cdp.coinbase.com/server-wallets/v2/introduction/welcome)
- [CDP Paymaster 文档](https://docs.cdp.coinbase.com/paymaster/introduction/welcome)
- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-2612 Permit 规范](https://eips.ethereum.org/EIPS/eip-2612)
- [Base Sepolia 区块浏览器](https://sepolia.basescan.org)

---

## 附录: 配置文件示例

### subscription-service/.env

```bash
# CDP 配置
CDP_API_KEY_ID=f211c826-054b-43dd-a8e5-427e3a1c4100
CDP_API_KEY_SECRET=your_secret_here
CDP_WALLET_SECRET=your_wallet_secret_here
CDP_SERVER_WALLET_ACCOUNT_NAME=openmesh-vpn-1775870994810
CDP_SERVER_WALLET_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3
CDP_PAYMASTER_ENDPOINT=https://api.developer.coinbase.com/rpc/v1/base-sepolia/NEBYVp2cH4KnkATJnEQ5BD9G38vB0Mk4

# 合约配置
VPN_SUBSCRIPTION_CONTRACT=0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
USDC_CONTRACT=0x036CbD53842c5426634e7929541eC2318f3dCF7e

# 服务配置
PORT=3000
SERVICE_WALLET_ADDRESS=0x729e71ff357ccefAa31635931621531082A698f6
RELAYER_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3

# 自动续费配置
RENEWAL_CHECK_INTERVAL_SECONDS=60
RENEWAL_PRECHECK_HOURS=24
MAX_RENEWAL_FAILS=3
```

---

**最后更新**: 2026-04-11  
**维护者**: OpenMesh Team  
**许可证**: MIT
