# CDP Smart Account + Paymaster 0 Gas 订阅解决方案

**创建时间**: 2026-04-12  
**状态**: ✅ 解决方案完整  
**关联问题**: "Insufficient balance to execute the transaction"

---

## 1. 问题根因诊断

你遇到的三个问题**同时存在**，必须全部修复才能实现 0 gas 订阅：

| # | 问题 | 现象 | 影响 |
|---|------|------|------|
| A | `sendUserOperation` 未传 `paymasterUrl` | Paymaster **不会自动启用** | 直接导致 "Insufficient balance" |
| B | CDP Portal 未配置合约 Allowlist | Paymaster 收到请求后**拒绝赞助** | 即使传了 URL 也会失败 |
| C | `waitForUserOperation` 未调用 | 无法确认交易是否上链 | 结果不可靠 |

---

## 2. 关键概念澄清

### `sendUserOperation` 不会自动使用 Paymaster

CDP SDK 的 `sendUserOperation` **默认不启用 Paymaster**。必须显式传入 `paymasterUrl` 参数，SDK 才会通过该 URL 向 Paymaster 请求 gas 赞助：

```javascript
// ❌ 当前代码 — 未传 paymasterUrl，Smart Account 自己付 gas（但它没有 ETH）
const userOp = await cdpClient.evm.sendUserOperation({
  smartAccount: serverWalletAccount,
  network: 'base-sepolia',
  calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }],
  // ← 缺少 paymasterUrl！
});

// ✅ 正确写法 — 显式指定 Paymaster URL
const userOp = await cdpClient.evm.sendUserOperation({
  smartAccount: serverWalletAccount,
  network: 'base-sepolia',
  calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }],
  paymasterUrl: process.env.CDP_PAYMASTER_URL,  // ← 必须加这一行
});
```

### Paymaster 必须 Allowlist 你的合约

CDP Paymaster 默认**不赞助任何合约**。你必须在 CDP Portal 中手动将 `VPNSubscription` 合约地址和 `permitAndSubscribe` 函数加入白名单，否则即使传了 `paymasterUrl`，请求也会被 Paymaster 拒绝。

---

## 3. 完整修复步骤

### 步骤一：CDP Portal 配置 Paymaster Allowlist

1. 登录 [https://portal.cdp.coinbase.com](https://portal.cdp.coinbase.com)
2. 选择你的项目
3. 左侧导航点击 **Paymaster**
4. 进入 **Configuration** 标签页
5. 顶部网络选择器选择 **Base Sepolia**
6. 确认 Paymaster 开关已**开启**（Enable）
7. 点击 **Add** 添加合约白名单：
   - **Contract Address**: 你的 `VPNSubscription.sol` 部署地址
   - **Function**: `permitAndSubscribe(address,address,uint256,uint256,uint256,uint256,bytes,uint8,bytes32,bytes32)`
8. 设置 **Per User Limit**（建议测试阶段先设置宽松值）：
   - Max UserOperations: `10`
   - Limit cycle: `Daily`
9. 设置 **Global Limit**（建议测试阶段先设置 `$5`）
10. 点击右上角 **Configuration** 页面复制 **RPC URL**（格式为 `https://api.developer.coinbase.com/rpc/v1/base-sepolia/<KEY>`）

### 步骤二：更新 .env 文件

```bash
# .env
CDP_API_KEY_ID=your-api-key-id
CDP_API_KEY_SECRET=your-api-key-secret
CDP_WALLET_SECRET=your-wallet-secret

# 从 CDP Portal > Paymaster > Configuration 复制
CDP_PAYMASTER_URL=https://api.developer.coinbase.com/rpc/v1/base-sepolia/NEBYVp2cH4KnkATJnEQ5BD9G38vB0Mk4
```

> ⚠️ 你的 `CDP_PAYMASTER_URL` 已经在问题描述中提供，直接存入 .env 即可，不要硬编码在代码里。

### 步骤三：修复后端代码（subscription-service/index.js）

```javascript
import { CdpClient } from '@coinbase/cdp-sdk';
import { encodeFunctionData } from 'viem';

// 模块级别初始化（不要在每次请求时重新 new）
const cdpClient = new CdpClient();

// 初始化 Smart Account（应用启动时执行一次）
let serverWalletAccount = null;

async function initSmartAccount() {
  const ownerAccount = await cdpClient.evm.getOrCreateAccount({
    name: 'openmesh-vpn-owner',
  });

  serverWalletAccount = await cdpClient.evm.getOrCreateSmartAccount({
    name: 'openmesh-vpn-smart',
    owner: ownerAccount,
  });

  console.log('Smart Account address:', serverWalletAccount.address);
}

// 订阅处理函数
async function handleSubscribe(req, res) {
  try {
    const {
      userAddress,
      identityAddress,
      planId,
      maxAmount,
      deadline,
      nonce,
      intentSignature,
      permitSignature,
    } = req.body;

    // 1. 验证签名（原有逻辑保持不变）
    // ...

    // 2. 解析 permit 签名
    const permitSig = {
      v: Number(permitSignature.v),
      r: permitSignature.r,
      s: permitSignature.s,
    };

    // 3. 用 viem 编码 calldata（uint256 必须用 BigInt）
    const calldata = encodeFunctionData({
      abi: CONTRACT_ABI,
      functionName: 'permitAndSubscribe',
      args: [
        userAddress,           // address
        identityAddress,       // address
        BigInt(planId),        // uint256 ← 必须 BigInt
        BigInt(maxAmount),     // uint256 ← 必须 BigInt
        BigInt(deadline),      // uint256 ← 必须 BigInt
        BigInt(nonce),         // uint256 ← 必须 BigInt
        intentSignature,       // bytes
        permitSig.v,           // uint8
        permitSig.r,           // bytes32
        permitSig.s,           // bytes32
      ],
    });

    // 4. 发送 UserOperation — 关键：传入 paymasterUrl
    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount,
      network: 'base-sepolia',
      calls: [{
        to: CONTRACT_ADDRESS,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,  // ← 核心修复点
    });

    console.log('UserOperation hash:', userOp.userOpHash);

    // 5. 等待 UserOperation 上链确认
    const receipt = await cdpClient.evm.waitForUserOperation({
      userOpHash: userOp.userOpHash,
      network: 'base-sepolia',
    });

    if (receipt.status !== 'success') {
      throw new Error(`UserOperation failed on-chain: ${receipt.status}`);
    }

    console.log('Transaction confirmed:', receipt.transactionHash);

    return res.json({
      success: true,
      userOpHash: userOp.userOpHash,
      transactionHash: receipt.transactionHash,
    });

  } catch (error) {
    console.error('Subscribe error:', error);
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
}
```

---

## 4. 架构全流程图

```
用户前端 (MetaMask)
    │
    │ 1. EIP-712 签名 (SubscribeIntent)
    │ 2. EIP-2612 签名 (USDC Permit)
    │
    ▼
后端 (subscription-service/index.js)
    │
    │ 3. 验证两个签名
    │ 4. encodeFunctionData → calldata
    │
    ▼
CDP SDK: cdpClient.evm.sendUserOperation({ paymasterUrl })
    │
    │ 5. SDK 向 CDP Paymaster 请求赞助
    │    POST https://api.developer.coinbase.com/rpc/v1/base-sepolia/<KEY>
    │    方法: pm_getPaymasterStubData → pm_getPaymasterData
    │
    ▼
CDP Paymaster
    │
    │ 6. 检查 Allowlist（合约地址 + 函数选择器）
    │ 7. 检查 Per User / Global 限额
    │ 8. 返回 paymasterAndData 字段（赞助证明）
    │
    ▼
CDP Bundler (ERC-4337)
    │
    │ 9. 打包 UserOperation（含 paymasterAndData）
    │ 10. 提交到 Base Sepolia EntryPoint 合约
    │
    ▼
VPNSubscription.sol: permitAndSubscribe(...)
    │
    │ 11. 验证 USDC Permit 签名
    │ 12. 划扣 USDC（用户授权的金额）
    │ 13. 激活订阅
    │
    ▼
后端: waitForUserOperation → 返回 transactionHash
```

---

## 5. 常见错误排查

### 错误：`Insufficient balance to execute the transaction`
**原因**: `sendUserOperation` 未传 `paymasterUrl`，Smart Account 试图自己付 gas 但余额为 0。  
**修复**: 加上 `paymasterUrl: process.env.CDP_PAYMASTER_URL`。

### 错误：`UserOperation rejected by paymaster`
**原因**: 合约地址或函数未在 CDP Portal 的 Allowlist 中配置。  
**修复**: 进入 CDP Portal > Paymaster > Configuration > 添加合约和函数。

### 错误：`paymaster: global limit exceeded`
**原因**: CDP Paymaster 的全局 gas 赞助额度已耗尽。  
**修复**: 进入 CDP Portal > Paymaster > Configuration > 提高 Global Limit。

### 错误：`paymaster: per user limit exceeded`
**原因**: 该用户地址触发了 Per User 限额。  
**修复**: 调整 Per User Limit 或 Limit Cycle 周期。

### 错误：`Invalid paymasterUrl`
**原因**: 环境变量未正确加载，或 URL 格式错误。  
**修复**: 确认 `.env` 中 `CDP_PAYMASTER_URL` 已设置，且以 `https://` 开头。

---

## 6. 验证清单

完成所有修复后，按顺序检查：

- [ ] CDP Portal > Paymaster > Configuration 已选中 **Base Sepolia**
- [ ] Paymaster 开关已**开启**
- [ ] 合约地址 + `permitAndSubscribe` 函数已添加到 **Allowlist**
- [ ] Per User Limit 和 Global Limit 已设置（且未耗尽）
- [ ] `.env` 文件包含 `CDP_PAYMASTER_URL`
- [ ] `sendUserOperation` 调用中已包含 `paymasterUrl` 参数
- [ ] `waitForUserOperation` 已调用并检查 `receipt.status === 'success'`
- [ ] 重启后端服务
- [ ] 执行完整订阅流程，前端无 500 错误
- [ ] 后端日志中出现 `UserOperation hash:` 和 `Transaction confirmed:` 两行输出
- [ ] 在 [https://sepolia.basescan.org](https://sepolia.basescan.org) 用 `transactionHash` 确认交易 Status 为 **Success**

---

## 7. 参考资料

- [CDP SDK sendUserOperation 文档](https://coinbase.github.io/cdp-sdk/typescript/)
- [CDP Paymaster 配置指南](https://docs.cdp.coinbase.com/paymaster/guides/paymaster-masterclass)
- [CDP Paymaster 安全最佳实践](https://docs.cdp.coinbase.com/paymaster/reference-troubleshooting/security)
- [Base 官方 Gasless Transactions 教程](https://docs.base.org/use-cases/go-gasless)

---

**更新日志**:
- 2026-04-12: 诊断 Paymaster 未启用的根本原因，提供完整修复方案
