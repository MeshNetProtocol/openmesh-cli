# EIP-3009 订阅系统快速启动指南

## 系统概述

本系统实现了基于 EIP-3009 的 USDC 订阅自动续费功能，用户首次订阅时批量签署 12 个月的授权，后续由 Relayer 自动提交续费，用户全程零 Gas。

**核心优势**：
- ✅ 用户零 Gas（CDP Paymaster 赞助）
- ✅ 批量预签名可靠（随机 bytes32 nonce，无冲突）
- ✅ 单次精确金额（无持续授权风险）
- ✅ 平滑过渡（保留 fallback 机制）

---

## 环境配置

### 1. 合约地址（Base Sepolia）

```bash
VPN_SUBSCRIPTION_CONTRACT=0x2c852fBFdCf5Fa1177f237d4cAc9872F7CDfB110
USDC_CONTRACT=0x036CbD53842c5426634e7929541eC2318f3dCF7e
SERVICE_WALLET_ADDRESS=0x729e71ff357ccefAa31635931621531082A698f6
RELAYER_ADDRESS=0x8c145d6ae710531A13952337Bf2e8A31916963F3
```

### 2. CDP 配置

```bash
CDP_API_KEY_ID=f211c826-054b-43dd-a8e5-427e3a1c4100
CDP_API_KEY_SECRET=XXCq/tQDmi0eaIfb3brbsL9Q9zUyngH9px4kZOfpXN0wy4P8VluPZ+1L9YnGzxsx2t79l/IXXS+7j574Y3rsHQ==
CDP_SERVER_WALLET_ACCOUNT_NAME=openmesh-vpn-1775870994810
CDP_PAYMASTER_URL=https://api.developer.coinbase.com/rpc/v1/base-sepolia/NEBYVp2cH4KnkATJnEQ5BD9G38vB0Mk4
```

---

## 快速启动

### 步骤 1: 安装依赖

```bash
cd subscription-service
npm install
```

### 步骤 2: 启动后端服务

```bash
npm start
```

服务将在 `http://localhost:3000` 启动。

### 步骤 3: 启动前端

```bash
cd ../frontend
# 使用任意 HTTP 服务器，例如：
python3 -m http.server 8080
# 或
npx http-server -p 8080
```

前端将在 `http://localhost:8080` 启动。

### 步骤 4: 准备测试钱包

1. 在 MetaMask 中切换到 Base Sepolia 测试网
2. 获取测试 ETH（用于首次 approve，如果需要）：
   - https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
3. 获取测试 USDC：
   - 合约地址：`0x036CbD53842c5426634e7929541eC2318f3dCF7e`
   - 可以从 Uniswap 或其他 DEX 兑换

---

## 测试流程

### 1. 首次订阅（生成 12 个月预签名）

1. 打开前端 `http://localhost:8080`
2. 点击"连接钱包"
3. 选择套餐并输入 VPN 身份地址
4. 点击"订阅"
5. **关键步骤**：MetaMask 会弹出 **13 次签名请求**
   - 第 1 次：订阅意图签名
   - 第 2-13 次：12 个月的 EIP-3009 预签名（每月一个）
6. 等待交易确认

**预期结果**：
- 订阅成功
- 后端存储了 12 个预签名
- 控制台显示：`已生成 12 个月的自动续费签名`

### 2. 查看预签名（可选）

```bash
# 查看某个身份的预签名
curl http://localhost:3000/api/subscription/presign/0xYourIdentityAddress
```

**预期返回**：
```json
{
  "success": true,
  "signatures": [
    {
      "from": "0x...",
      "to": "0x729e71ff357ccefAa31635931621531082A698f6",
      "value": "100000",
      "validAfter": 1744934400,
      "validBefore": 1747526400,
      "nonce": "0x...",
      "v": 27,
      "r": "0x...",
      "s": "0x..."
    },
    // ... 11 more signatures
  ]
}
```

### 3. 自动续费测试

**方式 1：等待自动触发**
- 自动续费服务每 60 秒检查一次
- 当订阅到期时，自动使用预签名续费

**方式 2：手动触发（测试用）**

修改 `.env` 中的续费检查间隔：
```bash
RENEWAL_CHECK_INTERVAL_SECONDS=10  # 改为 10 秒
RENEWAL_PRECHECK_HOURS=0.01        # 提前 36 秒预检
```

重启服务后，观察日志：
```
⏰ [2026-04-15T10:00:00.000Z] 执行自动续费检查...
  [0xIdentity] 🔐 使用 EIP-3009 预签名续费 (validAfter: 2026-04-15T09:00:00.000Z)
  [0xIdentity] 📤 发送 UserOperation (Paymaster 赞助 gas)...
  [0xIdentity] ✅ 续费成功! TX: 0x...
  [0xIdentity] 🗑️  已删除使用过的 EIP-3009 签名 (剩余: 11)
```

### 4. Fallback 机制测试

如果没有有效的 EIP-3009 签名，系统会自动回退到传统的 `executeRenewal` 方法：

```
  [0xIdentity] 📝 未找到有效的 EIP-3009 签名，使用传统 executeRenewal
  [0xIdentity] 📤 发送 UserOperation (Paymaster 赞助 gas)...
  [0xIdentity] ✅ 续费成功! TX: 0x...
```

---

## 验证检查清单

运行自动测试脚本：

```bash
./test-eip3009-system.sh
```

**预期结果**：
```
总测试数: 21
通过: 19
失败: 2  # API 测试失败是因为服务未运行，启动服务后会通过
```

**手动验证清单**：

- [ ] 环境变量配置一致（合约地址、USDC 地址、钱包地址）
- [ ] 合约包含 `renewWithAuthorization` 函数
- [ ] 后端包含 `/api/subscription/presign` 端点
- [ ] 前端包含 `generateEIP3009Signatures` 函数
- [ ] 订阅时生成 12 个预签名
- [ ] 预签名成功提交到后端
- [ ] 自动续费优先使用 EIP-3009 签名
- [ ] Fallback 机制正常工作
- [ ] 用户全程零 Gas

---

## 故障排查

### 问题 1: MetaMask 签名失败

**原因**：USDC 合约地址或 chainId 不正确

**解决**：
```javascript
// 检查 frontend/app.js 中的配置
const CONFIG = {
  CHAIN_ID: 84532, // Base Sepolia
  USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  CONTRACT_ADDRESS: '0x2c852fBFdCf5Fa1177f237d4cAc9872F7CDfB110'
};
```

### 问题 2: 续费时找不到签名

**原因**：签名未正确存储或已过期

**解决**：
```bash
# 检查签名存储
curl http://localhost:3000/api/subscription/presign/0xYourIdentityAddress

# 检查签名时间窗口
# validAfter 应该 <= 当前时间 < validBefore
```

### 问题 3: UserOperation 失败

**原因**：CDP Paymaster 配置错误或余额不足

**解决**：
```bash
# 检查 CDP 配置
echo $CDP_PAYMASTER_URL
echo $CDP_SERVER_WALLET_ACCOUNT_NAME

# 检查 CDP Server Wallet 余额（需要少量 ETH）
```

### 问题 4: 合约调用 revert

**原因**：
- 订阅未激活
- 自动续费未开启
- 订阅尚未到期
- 签名验证失败

**解决**：
```bash
# 检查订阅状态
curl http://localhost:3000/api/subscription/0xYourWalletAddress

# 查看合约事件日志
# 在 Base Sepolia Etherscan 查看交易详情
```

---

## 性能指标

### Gas 消耗（由 CDP Paymaster 赞助）

- 首次订阅：~150,000 gas
- EIP-3009 续费：~100,000 gas
- 传统续费（executeRenewal）：~120,000 gas

### 用户体验

- 首次订阅签名次数：13 次（1 次订阅意图 + 12 次 EIP-3009）
- 首次订阅时间：~2 分钟（包括签名和交易确认）
- 自动续费：零交互，后台自动完成
- 续费延迟：< 1 分钟（从到期到续费完成）

---

## 下一步

1. **生产环境部署**：
   - 切换到 Base 主网
   - 更新合约地址和 USDC 地址
   - 配置生产环境的 CDP Paymaster

2. **监控和告警**：
   - 监控 Relayer 余额
   - 监控续费成功率
   - 设置签名即将用完的告警

3. **用户体验优化**：
   - 添加签名进度条
   - 添加签名剩余数量显示
   - 添加签名刷新功能（第 12 个月到期前）

4. **安全加固**：
   - 加密存储预签名
   - 添加签名验证
   - 实现签名备份和恢复

---

## 参考文档

- [EIP3009_MIGRATION_SUMMARY.md](EIP3009_MIGRATION_SUMMARY.md) - 迁移总结
- [blockchain_subscription_ultimate_solution.md](blockchain_subscription_ultimate_solution.md) - 技术调研
- [Circle 官方博客](https://www.circle.com/blog/four-ways-to-authorize-usdc-smart-contract-interactions-with-circle-sdk) - EIP-3009 详解
- [EIP-3009 标准](https://eips.ethereum.org/EIPS/eip-3009) - 官方规范

---

**系统状态**：✅ 已完成开发，准备测试

**最后更新**：2026-04-15
