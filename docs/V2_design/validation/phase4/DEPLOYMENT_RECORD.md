# VPNSubscription V2.1 部署记录

**部署时间**: 2026-04-13 16:14  
**网络**: Base Sepolia Testnet  
**状态**: ✅ 部署成功

---

## 部署信息

### 合约地址
```
0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf
```

### 部署者地址
```
0x490DC2F60aececAFF22BC670166cbb9d5DdB9241
```

### 配置参数

| 参数 | 地址 | 说明 |
|------|------|------|
| USDC Contract | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Base Sepolia USDC |
| Service Wallet | `0x729e71ff357ccefAa31635931621531082A698f6` | 接收 USDC 支付 |
| Relayer | `0x8c145d6ae710531A13952337Bf2e8A31916963F3` | CDP Server Wallet |

### Gas 消耗

- **Gas Used**: 5,362,394
- **Gas Price**: 0.011 gwei
- **Total Cost**: 0.000058986334 ETH

---

## 初始化套餐

合约在构造函数中自动初始化了三个套餐:

### Plan 1: Free
- **价格**: 0 USDC
- **流量限制**: 100 MB/天
- **适用场景**: 轻度使用,试用

### Plan 2: Basic
- **月付价格**: 5 USDC/月
- **年付价格**: 50 USDC/年
- **流量限制**: 100 GB/月
- **适用场景**: 中度使用

### Plan 3: Premium
- **月付价格**: 10 USDC/月
- **年付价格**: 100 USDC/年
- **流量限制**: 无限
- **适用场景**: 重度使用

---

## 合约验证

**状态**: ⚠️ 待验证

**原因**: Etherscan API key 达到请求限制

**手动验证命令**:
```bash
forge verify-contract \
  --chain-id 84532 \
  --num-of-optimizations 200 \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x036CbD53842c5426634e7929541eC2318f3dCF7e 0x729e71ff357ccefAa31635931621531082A698f6 0x8c145d6ae710531A13952337Bf2e8A31916963F3) \
  --etherscan-api-key YOUR_API_KEY \
  --compiler-version v0.8.24+commit.e11b9ed9 \
  0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf \
  src/VPNSubscriptionV2.sol:VPNSubscription
```

**或者在 Basescan 上手动验证**:
1. 访问: https://sepolia.basescan.org/address/0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf#code
2. 点击 "Verify and Publish"
3. 选择 Solidity (Single file)
4. Compiler: v0.8.24+commit.e11b9ed9
5. Optimization: Yes, 200 runs
6. Constructor Arguments: `000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e000000000000000000000000729e71ff357ccefaa31635931621531082a698f60000000000000000000000008c145d6ae710531a13952337bf2e8a31916963f3`

---

## 区块链浏览器链接

- **Basescan**: https://sepolia.basescan.org/address/0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf
- **部署交易**: https://sepolia.basescan.org/tx/[DEPLOYMENT_TX_HASH]

---

## 下一步操作

### 1. 更新 CDP Paymaster 白名单

访问 [CDP Dashboard](https://portal.cdp.coinbase.com/) 并添加新合约地址到 Paymaster 白名单:

```
0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf
```

### 2. 更新后端配置

更新后端 `.env` 文件:

```bash
VPN_SUBSCRIPTION_CONTRACT=0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf
```

### 3. 更新前端配置

更新前端合约地址配置:

```javascript
const VPN_SUBSCRIPTION_ADDRESS = "0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf";
```

### 4. 验证合约

等待 Etherscan API 限制解除后,运行验证命令或手动验证。

### 5. 测试合约功能

- 测试订阅创建 (Free/Basic/Premium)
- 测试流量上报和限制
- 测试订阅升级/降级
- 测试自动续费

---

## 合约功能清单

### ✅ 已实现功能

- [x] 三级套餐系统 (Free/Basic/Premium)
- [x] 月付/年付支持
- [x] 流量限制和追踪 (日限/月限)
- [x] 订阅升级 (立即生效 + Proration 补差价)
- [x] 订阅降级 (下周期生效)
- [x] 取消待生效变更
- [x] 自动续费 (应用待生效变更)
- [x] EIP-712 签名验证
- [x] ERC-2612 Permit (gasless approvals)
- [x] 多身份订阅支持
- [x] 流量超限自动暂停
- [x] 流量重置 (日/月)

### 📋 测试覆盖

- 31/31 单元测试通过
- 套餐管理测试: 5/5 ✅
- 流量管理测试: 8/8 ✅
- Proration 算法测试: 5/5 ✅
- 订阅变更测试: 8/8 ✅
- 集成测试: 5/5 ✅

---

## 技术规格

- **Solidity 版本**: 0.8.24
- **优化**: 启用 (200 runs)
- **Via IR**: 启用
- **依赖**:
  - OpenZeppelin Contracts 5.0.2
  - EIP-712 (Typed Structured Data)
  - ERC-2612 (Permit)
  - ERC-20 (USDC)

---

## 安全特性

- ✅ ReentrancyGuard (防重入攻击)
- ✅ Pausable (紧急暂停)
- ✅ Ownable (权限控制)
- ✅ EIP-712 签名验证 (防签名伪造)
- ✅ Nonce 机制 (防重放攻击)
- ✅ SafeERC20 (安全的 ERC-20 操作)

---

**文档版本**: V1.0  
**最后更新**: 2026-04-13 16:14  
**作者**: Claude Code
