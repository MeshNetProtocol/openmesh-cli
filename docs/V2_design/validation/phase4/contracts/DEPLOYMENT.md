# VPNSubscription 合约部署指南

## 前置准备

### 1. 准备钱包和测试币

**获取 Base Sepolia 测试 ETH:**
- 方式 1: Coinbase 水龙头 - https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
- 方式 2: Base 官方水龙头 - https://sepolia-faucet.base.org/

**检查余额:**
你的钱包需要至少 0.01 ETH 来支付部署 gas 费用。

### 2. 配置环境变量

复制 `.env.example` 到 `.env`:
```bash
cd contracts
cp .env.example .env
```

编辑 `.env` 文件,填入以下信息:

**方式 1: 使用助记词 (推荐)**
```bash
# 你的 MetaMask 助记词 (12 或 24 个单词)
MNEMONIC=your twelve word mnemonic phrase goes here

# 助记词账户索引 (默认: 0 表示第一个账户)
MNEMONIC_INDEX=0

# 服务钱包地址 (接收 USDC 支付)
SERVICE_WALLET_ADDRESS=0x729e71ff357ccefAa31635931621531082A698f6

# Relayer 地址 (CDP Server Wallet 地址)
RELAYER_ADDRESS=your_cdp_server_wallet_address_here
```

**方式 2: 使用私钥**
```bash
# 你的 MetaMask 私钥 (不要包含 0x 前缀)
PRIVATE_KEY=your_private_key_here

# 服务钱包地址和 Relayer 地址同上
```

**重要提示:**
- 永远不要提交包含真实助记词或私钥的 `.env` 文件!
- `.env` 文件已经在 `.gitignore` 中被排除
- 使用助记词更安全,因为你不需要导出私钥

### 3. 获取 CDP Server Wallet 地址

如果你还没有创建 CDP Server Wallet:

1. 访问 CDP 控制台: https://portal.cdp.coinbase.com/
2. 创建一个新的 Server Wallet
3. 复制钱包地址作为 `RELAYER_ADDRESS`

## 部署步骤

### 1. 编译合约

```bash
cd contracts
forge build
```

### 2. 模拟部署 (Dry Run)

在实际部署前,先模拟部署来检查是否有问题:

```bash
forge script script/DeployVPNSubscription.s.sol:DeployVPNSubscription \
  --rpc-url base-sepolia \
  --private-key $PRIVATE_KEY
```

### 3. 实际部署

确认模拟部署成功后,执行实际部署:

```bash
forge script script/DeployVPNSubscription.s.sol:DeployVPNSubscription \
  --rpc-url base-sepolia \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

参数说明:
- `--broadcast`: 实际发送交易到链上
- `--verify`: 自动在 BaseScan 上验证合约

### 4. 记录部署信息

部署成功后,你会看到类似输出:

```
VPNSubscription deployed to: 0x1234567890123456789012345678901234567890
USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
Service Wallet: 0x729e71ff357ccefAa31635931621531082A698f6
Relayer: 0xYourCDPServerWalletAddress
```

**重要:** 保存合约地址,后续前端和后端都需要使用!

## 验证部署

### 1. 在 BaseScan 上查看

访问: https://sepolia.basescan.org/address/YOUR_CONTRACT_ADDRESS

你应该能看到:
- 合约代码已验证 (绿色勾号)
- 构造函数参数
- 合约 ABI

### 2. 测试合约调用

使用 cast 工具测试读取合约状态:

```bash
# 查看 Plan 1 (月付套餐)
cast call YOUR_CONTRACT_ADDRESS "plans(uint256)(uint256,uint256,bool)" 1 \
  --rpc-url base-sepolia

# 查看 relayer 地址
cast call YOUR_CONTRACT_ADDRESS "relayer()(address)" \
  --rpc-url base-sepolia

# 查看 serviceWallet 地址
cast call YOUR_CONTRACT_ADDRESS "serviceWallet()(address)" \
  --rpc-url base-sepolia
```

## 部署后配置

### 1. 更新后端配置

在 `phase4/.env` 中添加合约地址:

```bash
VPN_SUBSCRIPTION_CONTRACT=0xYourContractAddress
```

### 2. 更新前端配置

在 `phase4/web/subscribe.html` 中更新合约地址:

```javascript
const CONTRACT_ADDRESS = '0xYourContractAddress';
```

### 3. 配置 CDP Paymaster

1. 访问 CDP 控制台
2. 配置 Paymaster 白名单:
   - 添加合约地址: `0xYourContractAddress`
   - 允许的方法: `permitAndSubscribe`, `executeRenewal`, `cancelFor`, `finalizeExpired`
3. 设置月度 gas 上限: $50

## 故障排查

### 部署失败: "insufficient funds"
- 检查钱包是否有足够的 Base Sepolia ETH
- 至少需要 0.01 ETH

### 部署失败: "invalid private key"
- 确保私钥不包含 `0x` 前缀
- 确保私钥是 64 个十六进制字符

### 验证失败
- 等待几分钟后重试
- 手动验证: 访问 BaseScan → Verify & Publish

### 合约调用失败: "not relayer"
- 确保 `RELAYER_ADDRESS` 配置正确
- 确保后端使用的是 CDP Server Wallet 地址

## 合约地址记录

部署完成后,在此记录合约地址:

```
Network: Base Sepolia
Contract Address: 
Deployer: 
Deployment Date: 
Transaction Hash: 
BaseScan: https://sepolia.basescan.org/address/
```

## 下一步

部署完成后:
1. ✅ 更新前端合约地址
2. ✅ 更新后端合约地址
3. ✅ 配置 CDP Paymaster
4. ✅ 测试完整订阅流程
