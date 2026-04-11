# Phase 4 部署总结

## 部署时间
2026-04-11

## 1. CDP Server Wallet

已成功创建 CDP Server Wallet 用于自动续费:

```
Account Name: openmesh-vpn-1775870994810
Address: 0x8c145d6ae710531A13952337Bf2e8A31916963F3
Network: base-sepolia
```

**用途:** 作为 Relayer 地址,用于调用 `executeRenewal()` 实现自动续费功能。

## 2. VPNSubscription 智能合约

已成功部署到 Base Sepolia 测试网:

```
合约地址: 0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
USDC 地址: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
Service Wallet: 0x729e71ff357ccefAa31635931621531082A698f6
Relayer: 0x8c145d6ae710531A13952337Bf2e8A31916963F3
```

**部署信息:**
- Gas 使用: 2,619,514
- 实际花费: 0.000015717084 ETH
- 部署账户: 0x729e71ff357ccefAa31635931621531082A698f6

## 3. 配置文件

### phase4/.env
```bash
# CDP Server Wallet
CDP_SERVER_WALLET_ACCOUNT_NAME=openmesh-vpn-1775870994810
CDP_SERVER_WALLET_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3

# 智能合约
VPN_SUBSCRIPTION_CONTRACT=0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
USDC_CONTRACT=0x036CbD53842c5426634e7929541eC2318f3dCF7e

# 收款地址
SERVICE_WALLET_ADDRESS=0x729e71ff357ccefAa31635931621531082A698f6
RELAYER_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3
```

### contracts/.env
```bash
PRIVATE_KEY=0x029383f905828598c37853acaa2124209125dae1b9a6e98e04339bb45c744c2e
SERVICE_WALLET_ADDRESS=0x729e71ff357ccefAa31635931621531082A698f6
RELAYER_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3
```

## 4. 下一步工作

### 4.1 配置订阅计划
在合约中添加订阅计划:
```bash
# 示例: 添加周订阅计划
cast send $VPN_SUBSCRIPTION_CONTRACT \
  "addPlan(string,uint256,uint256)" \
  "weekly_test" \
  "1000000" \
  "604800" \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia.base.org
```

### 4.2 启动后端服务
```bash
cd service
npm install
npm run dev
```

### 4.3 测试订阅流程
1. 用户获取 USDC 测试币
2. 用户调用 `permitAndSubscribe()` 订阅
3. 后端监听订阅事件
4. 后端定期检查并执行自动续费

### 4.4 CDP Server Wallet 充值
CDP Server Wallet 需要有 ETH 来支付 gas 费用:
```bash
# 从水龙头获取测试 ETH
# 发送到: 0x8c145d6ae710531A13952337Bf2e8A31916963F3
```

## 5. 验证部署

### 5.1 验证合约部署
```bash
cast call $VPN_SUBSCRIPTION_CONTRACT "usdc()" --rpc-url https://sepolia.base.org
cast call $VPN_SUBSCRIPTION_CONTRACT "serviceWallet()" --rpc-url https://sepolia.base.org
cast call $VPN_SUBSCRIPTION_CONTRACT "relayer()" --rpc-url https://sepolia.base.org
```

### 5.2 查看合约信息
Base Sepolia 区块浏览器:
https://sepolia.basescan.org/address/0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2

## 6. 重要提醒

⚠️ **安全提示:**
1. 所有私钥和助记词都已配置在 `.env` 文件中
2. `.env` 文件已在 `.gitignore` 中排除,不会被提交到 git
3. 这是测试网部署,使用的是测试币,没有真实价值
4. 生产环境部署时需要使用新的私钥和更严格的安全措施

⚠️ **CDP Server Wallet 管理:**
1. Account Name `openmesh-vpn-1775870994810` 是唯一标识符
2. 可以使用 `cdp.evm.getOrCreateAccount({ name: "openmesh-vpn-1775870994810" })` 获取账户
3. CDP Wallet Secret 已保存在 `.env` 文件中,请妥善保管

## 7. 故障排查

如果遇到问题,请检查:
1. CDP Server Wallet 是否有足够的 ETH 支付 gas
2. 合约地址是否正确配置在 `.env` 文件中
3. USDC 合约地址是否正确 (Base Sepolia: 0x036CbD53842c5426634e7929541eC2318f3dCF7e)
4. Relayer 地址是否与 CDP Server Wallet 地址一致
