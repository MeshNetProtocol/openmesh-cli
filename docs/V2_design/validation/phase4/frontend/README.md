# OpenMesh VPN 订阅前端示例

这是一个简单的前端示例,展示如何集成 OpenMesh VPN 订阅服务。

## 功能特性

- 连接 MetaMask 钱包
- 查看 USDC 余额和订阅状态
- 使用 EIP-712 签名订阅服务
- 通过 CDP Paymaster 实现 0 ETH Gas
- 取消订阅和刷新状态

## 快速开始

### 1. 启动后端服务

```bash
cd docs/V2_design/validation/phase4/subscription-service
npm install
npm start
```

后端服务将在 `http://localhost:3000` 启动。

### 2. 启动前端

使用任意 HTTP 服务器启动前端:

```bash
cd docs/V2_design/validation/phase4/frontend

# 使用 Python
python3 -m http.server 8080

# 或使用 Node.js http-server
npx http-server -p 8080
```

访问 `http://localhost:8080`

### 3. 配置 MetaMask

1. 添加 Base Sepolia 测试网:
   - 网络名称: Base Sepolia
   - RPC URL: `https://sepolia.base.org`
   - Chain ID: `84532`
   - 货币符号: ETH
   - 区块浏览器: `https://sepolia.basescan.org`

2. 获取测试 USDC:
   - 访问 [Circle Faucet](https://faucet.circle.com/)
   - 输入你的钱包地址
   - 选择 Base Sepolia 网络
   - 领取测试 USDC

## 使用流程

1. 点击"连接 MetaMask"按钮
2. 在 MetaMask 中确认连接
3. 查看你的 USDC 余额和订阅状态
4. 选择订阅套餐 (月付或年付)
5. 输入 VPN 身份地址 (用于准入控制)
6. 点击"订阅"按钮
7. 在 MetaMask 中签名两次:
   - 第一次: EIP-712 订阅签名
   - 第二次: USDC Permit 授权签名
8. 等待交易确认 (通过 CDP Paymaster,无需 ETH)

## 技术实现

### EIP-712 签名

前端使用 EIP-712 标准生成结构化签名:

```javascript
const signature = await signer._signTypedData(domain, types, value);
```

### API 调用流程

1. `POST /api/subscription/prepare` - 获取签名数据
2. 用户在 MetaMask 中签名
3. `POST /api/subscription/subscribe` - 提交订阅
4. 后端通过 CDP Paymaster 执行链上交易

### 0 ETH Gas 实现

所有交易通过 Coinbase Developer Platform 的 Paymaster 赞助 gas:

- 用户只需持有 USDC
- 无需持有 ETH 支付 gas
- 后端自动处理 gas 赞助

## 文件说明

- `index.html` - 前端页面
- `app.js` - 前端逻辑 (钱包连接、签名、API 调用)
- `README.md` - 本文档

## 配置说明

在 `app.js` 中修改配置:

```javascript
const CONFIG = {
  API_BASE: 'http://localhost:3000/api',  // 后端 API 地址
  CHAIN_ID: 84532,                         // Base Sepolia
  USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  CONTRACT_ADDRESS: '0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2'
};
```

## 常见问题

### 1. MetaMask 连接失败

- 确保已安装 MetaMask 扩展
- 确保已切换到 Base Sepolia 网络

### 2. USDC 余额为 0

- 访问 Circle Faucet 领取测试 USDC
- 确认交易已确认

### 3. 订阅失败

- 检查 USDC 余额是否足够
- 检查后端服务是否正常运行
- 查看浏览器控制台错误信息

### 4. 签名被拒绝

- 在 MetaMask 中点击"签名"而不是"拒绝"
- 确保理解签名内容后再确认

## 安全提示

- 这是测试网示例,不要在主网使用
- 不要在生产环境中硬编码私钥
- 始终验证签名内容后再确认
- 定期检查订阅状态和余额

## 下一步

- 集成到实际 VPN 客户端
- 添加订阅历史记录
- 实现自动续费提醒
- 添加多语言支持
