# 合约部署配置说明

本目录包含 VPNCreditVaultV4 合约的部署配置文件。

## 配置文件说明

### 测试网配置
- `testnet.env` - Base Sepolia 测试网配置
- 用于开发和测试环境
- 包含测试网的 USDC 合约地址和 RPC URL

### 正式网配置
- `mainnet.env` - Base Mainnet 正式网配置
- 用于生产环境部署
- **重要：包含真实的私钥和资金，请妥善保管**

### 当前使用的配置
- `.env` - 默认使用测试网配置

## 使用方法

### 测试网部署

```bash
# 使用默认的 .env 文件（已配置为测试网）
forge script script/DeployVPNCreditVaultV4.s.sol:DeployVPNCreditVaultV4 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify

# 或者显式指定测试网配置
cp testnet.env .env
forge script script/DeployVPNCreditVaultV4.s.sol:DeployVPNCreditVaultV4 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify
```

### 正式网部署

```bash
# 切换到正式网配置
cp mainnet.env .env

# 确认配置正确后再部署
cat .env

# 部署到 Base Mainnet
forge script script/DeployVPNCreditVaultV4.s.sol:DeployVPNCreditVaultV4 \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --broadcast \
    --verify
```

## 安全注意事项

1. **永远不要提交包含真实私钥的 .env 文件到 git**
2. `mainnet.env` 包含生产环境的敏感信息，请：
   - 使用环境变量或密钥管理服务
   - 限制文件访问权限：`chmod 600 mainnet.env`
   - 定期轮换私钥
3. 部署到正式网前：
   - 仔细检查所有配置参数
   - 确认合约地址正确
   - 在测试网充分测试后再部署
4. `.gitignore` 已配置忽略所有 `*.env` 文件，确保不会意外提交

## 配置项说明

| 配置项 | 说明 |
|--------|------|
| `PRIVATE_KEY` | 部署账户私钥（不含 0x 前缀） |
| `SERVICE_WALLET_ADDRESS` | 接收 USDC 支付的服务钱包地址 |
| `RELAYER_ADDRESS` | CDP 服务器钱包地址，用于调用合约方法 |
| `USDC_CONTRACT` | USDC 代币合约地址（测试网/正式网不同） |
| `BASE_SEPOLIA_RPC_URL` / `BASE_MAINNET_RPC_URL` | RPC 节点 URL |
| `VPN_CREDIT_VAULT_V4_CONTRACT` | 已部署的合约地址 |

## USDC 合约地址

- **Base Sepolia (测试网)**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- **Base Mainnet (正式网)**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

## 参考链接

- [Base 官方文档](https://docs.base.org/)
- [Base Sepolia 浏览器](https://sepolia.basescan.org/)
- [Base Mainnet 浏览器](https://basescan.org/)
- [USDC on Base](https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913)
