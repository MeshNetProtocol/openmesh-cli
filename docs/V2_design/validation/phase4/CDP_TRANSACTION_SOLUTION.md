# CDP Server Wallet 交易发送问题 — 解决方案

**创建时间**: 2026-04-11  
**状态**: ✅ 已解决  
**关联文档**: `CDP_TRANSACTION_DEBUG.md`

---

## 1. 根本原因

错误 `Malformed unsigned EIP-1559 transaction` 由以下两个原因共同导致：

### 原因 A：调用方式错误（最主要原因）

原代码直接在 `serverWalletAccount` 对象上调用 `sendTransaction`，并将 `to`、`data`、`network` 平铺传入：

```javascript
// ❌ 错误写法
const txResult = await serverWalletAccount.sendTransaction({
  to: CONTRACT_ADDRESS,
  data: calldata,
  network: 'base-sepolia',
});
```

CDP SDK v2 的正确签名是通过 **`cdp.evm.sendTransaction()`**，且交易字段必须嵌套在 `transaction` 子对象内：

```javascript
// ✅ 正确写法
const txResult = await cdp.evm.sendTransaction({
  address: serverWalletAccount.address,
  network: 'base-sepolia',
  transaction: {
    to: CONTRACT_ADDRESS,
    data: calldata,
    value: BigInt(0),
  },
});
```

### 原因 B：calldata 编码工具不匹配

原代码使用 `ethers.Interface.encodeFunctionData()` 生成 calldata。虽然 CDP SDK 本身能接受标准 hex string，但官方示例统一使用 **`viem` 的 `encodeFunctionData`**，两者在某些边界情况（如 `bytes` 类型的补零方式）存在细微差异，可能导致 ABI 编码不一致。

---

## 2. 完整修复方案

### 步骤 1：安装 viem（如尚未安装）

```bash
npm install viem
```

### 步骤 2：替换 calldata 编码方式

```javascript
// 旧：使用 ethers.js
import { ethers } from 'ethers';
const contractInterface = new ethers.Interface(CONTRACT_ABI);
const calldata = contractInterface.encodeFunctionData('permitAndSubscribe', [...args]);

// 新：使用 viem
import { encodeFunctionData } from 'viem';
const calldata = encodeFunctionData({
  abi: CONTRACT_ABI,
  functionName: 'permitAndSubscribe',
  args: [
    userAddress,          // address  → string '0x...'
    identityAddress,      // address  → string '0x...'
    BigInt(planId),       // uint256  → BigInt
    BigInt(maxAmount),    // uint256  → BigInt
    BigInt(deadline),     // uint256  → BigInt
    BigInt(nonce),        // uint256  → BigInt
    intentSignature,      // bytes    → hex string '0x...'
    permitSig.v,          // uint8    → number
    permitSig.r,          // bytes32  → hex string '0x...'
    permitSig.s,          // bytes32  → hex string '0x...'
  ],
});
```

> **关键**：`uint256` 类型必须传 `BigInt`，不能传普通 number 或 string，否则 viem 会抛出类型错误。

### 步骤 3：修复 sendTransaction 调用

```javascript
import { CdpClient } from '@coinbase/cdp-sdk';

const cdp = new CdpClient(); // 使用环境变量 CDP_API_KEY_ID / CDP_API_KEY_SECRET / CDP_WALLET_SECRET

// 获取已有的 Server Wallet 账户
const serverWalletAccount = await cdp.evm.getOrCreateAccount({ name: 'YourServerWallet' });

// 发送合约调用交易
const txResult = await cdp.evm.sendTransaction({
  address: serverWalletAccount.address,   // Server Wallet 地址
  network: 'base-sepolia',               // 网络标识符
  transaction: {
    to: CONTRACT_ADDRESS,                 // 合约地址
    data: calldata,                       // viem 编码的 calldata
    value: BigInt(0),                     // 无 ETH 转账时传 BigInt(0)
  },
});

console.log('Transaction Hash:', txResult.transactionHash);
```

### 步骤 4：完整的修复后代码（subscription-service/index.js 第 221-310 行）

```javascript
import { CdpClient } from '@coinbase/cdp-sdk';
import { encodeFunctionData } from 'viem';

// 初始化 CDP 客户端（复用，不要在每次请求时重新创建）
const cdp = new CdpClient();

async function handleSubscribe(req, res) {
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

  // 3. 编码 calldata（使用 viem）
  const calldata = encodeFunctionData({
    abi: CONTRACT_ABI,
    functionName: 'permitAndSubscribe',
    args: [
      userAddress,
      identityAddress,
      BigInt(planId),
      BigInt(maxAmount),
      BigInt(deadline),
      BigInt(nonce),
      intentSignature,
      permitSig.v,
      permitSig.r,
      permitSig.s,
    ],
  });

  // 4. 获取 Server Wallet 账户
  const serverWalletAccount = await cdp.evm.getOrCreateAccount({
    name: process.env.CDP_SERVER_WALLET_NAME || 'SubscriptionServiceWallet',
  });

  // 5. 发送交易（正确的 API 调用方式）
  const txResult = await cdp.evm.sendTransaction({
    address: serverWalletAccount.address,
    network: 'base-sepolia',
    transaction: {
      to: CONTRACT_ADDRESS,
      data: calldata,
      value: BigInt(0),
    },
  });

  return res.json({
    success: true,
    transactionHash: txResult.transactionHash,
  });
}
```

---

## 3. 参数类型速查表

| Solidity 类型 | viem 传参类型 | 示例 |
|--------------|--------------|------|
| `address`    | `string`     | `'0xAbCd...'` |
| `uint256`    | `BigInt`     | `BigInt(1000000)` 或 `1000000n` |
| `uint8`      | `number`     | `27` |
| `bytes`      | `hex string` | `'0x1a2b...'` |
| `bytes32`    | `hex string` | `'0xabcd...ef'`（必须 66 字符） |
| `bool`       | `boolean`    | `true` / `false` |

---

## 4. 常见陷阱与注意事项

### ⚠️ 陷阱 1：不要在请求处理函数内重复初始化 CdpClient

```javascript
// ❌ 每次请求都 new CdpClient() 会导致性能问题
app.post('/subscribe', async (req, res) => {
  const cdp = new CdpClient(); // 不要放在这里
});

// ✅ 模块级别初始化一次
const cdp = new CdpClient();
app.post('/subscribe', async (req, res) => {
  // 直接使用 cdp
});
```

### ⚠️ 陷阱 2：`network` 参数格式

CDP SDK 使用字符串 `'base-sepolia'`（连字符），而非 `'baseSepolia'`（驼峰）或链 ID 数字。

```javascript
// ✅ 正确
network: 'base-sepolia'

// ❌ 错误（会导致网络找不到错误）
network: 'baseSepolia'
network: 84532
```

### ⚠️ 陷阱 3：Gas 由 CDP 自动管理

CDP Server Wallet 会自动处理 nonce 和 gas，**不需要**也**不应该**手动传入 `gasLimit`、`maxFeePerGas`、`nonce` 等字段，传入反而可能引起冲突。

### ⚠️ 陷阱 4：等待交易确认

`cdp.evm.sendTransaction()` 只负责提交交易并返回 hash，不会等待链上确认。如果业务需要等待确认，使用 viem 的 `publicClient.waitForTransactionReceipt()`：

```javascript
import { createPublicClient, http } from 'viem';
import { baseSepolia } from 'viem/chains';

const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(),
});

const receipt = await publicClient.waitForTransactionReceipt({
  hash: txResult.transactionHash,
});
console.log('Confirmed in block:', receipt.blockNumber);
```

---

## 5. 验证步骤

修复后按以下顺序验证：

1. **重启服务**：`npm restart` 或重启对应进程
2. **执行完整订阅流程**：触发两次签名 → 调用订阅接口
3. **检查服务日志**：确认无 `Malformed unsigned EIP-1559 transaction` 错误
4. **检查返回值**：响应中应包含 `transactionHash`
5. **链上验证**：在 [Basescan Sepolia](https://sepolia.basescan.org) 查询交易哈希，确认状态为 Success

---

## 6. 依赖版本参考

| 依赖 | 推荐版本 |
|------|---------|
| `@coinbase/cdp-sdk` | `^1.46.0`（当前版本） |
| `viem` | `^2.x` |
| Node.js | `>=22.x` |

---

**更新日志**：
- 2026-04-11：分析问题根因，撰写完整解决方案
