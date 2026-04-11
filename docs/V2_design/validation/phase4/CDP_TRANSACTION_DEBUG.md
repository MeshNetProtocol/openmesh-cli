# CDP Server Wallet 交易发送问题诊断与解决方案

**创建时间**: 2026-04-11  
**状态**: 🔴 问题诊断中

---

## 1. 问题描述

### 当前错误
```
APIError: Malformed unsigned EIP-1559 transaction.
statusCode: 400
errorType: 'malformed_transaction'
```

### 错误发生位置
- **文件**: `subscription-service/index.js:284`
- **代码**:
```javascript
const txResult = await serverWalletAccount.sendTransaction({
  to: CONTRACT_ADDRESS,
  data: calldata,
  network: 'base-sepolia',
});
```

### 问题上下文
- 用户完成了两次签名(SubscribeIntent + USDC Permit)
- 后端成功验证了签名
- 在调用 CDP Server Wallet 的 `sendTransaction` 方法时失败
- 错误提示交易格式不正确

---

## 2. 根本原因分析

### 可能的原因
1. **calldata 格式问题**: 
   - 使用 `ethers.Interface.encodeFunctionData()` 生成的 calldata 格式可能不符合 CDP SDK 的要求
   - 需要确认 CDP SDK 期望的 calldata 格式

2. **参数缺失或格式错误**:
   - `network` 参数格式可能不对
   - 可能缺少其他必需参数(如 `value`, `gasLimit` 等)

3. **CDP SDK 版本问题**:
   - 当前使用的 CDP SDK 版本: `@coinbase/cdp-sdk@^1.46.0`
   - 可能 API 已经变更

### 需要验证的假设
- [ ] CDP SDK 的 `sendTransaction` 方法的正确参数格式
- [ ] calldata 是否需要特殊编码
- [ ] 是否需要额外的交易参数

---

## 3. 解决思路

### 步骤 1: 查阅官方文档
**目标**: 找到 CDP Server Wallet `sendTransaction` 的正确用法

**资源**:
- 官方文档: https://docs.cdp.coinbase.com/server-wallets/v2/introduction/welcome
- EVM 交易文档: https://docs.cdp.coinbase.com/server-wallets/v2/evm-features/sending-transactions
- SDK 文档: https://mintlify.wiki/coinbase/cdp-sdk/guides/sending-transactions

**需要查找的信息**:
1. `sendTransaction` 方法的完整参数列表
2. calldata 的正确格式
3. 是否有合约调用的示例代码
4. EIP-1559 交易的特殊要求

### 步骤 2: 查看 CDP SDK 源码
**目标**: 理解 SDK 内部如何处理交易

**需要检查**:
1. `sendTransaction` 方法的实现
2. 参数验证逻辑
3. 交易构造过程

### 步骤 3: 对比工作示例
**目标**: 找到成功的合约调用示例

**资源**:
- GitHub 搜索: CDP SDK 合约调用示例
- 官方示例代码
- 社区实现

### 步骤 4: 实施修复
**目标**: 根据文档和示例修复代码

**可能的修复方案**:
1. 调整 `sendTransaction` 参数格式
2. 修改 calldata 编码方式
3. 添加缺失的参数

---

## 4. 执行计划

### Phase 1: 文档研究 (优先级: P0)
- [ ] 阅读 CDP Server Wallet 官方文档
- [ ] 查找 `sendTransaction` API 参考
- [ ] 查找合约调用示例代码
- [ ] 记录正确的参数格式

### Phase 2: 代码分析 (优先级: P0)
- [ ] 检查当前 calldata 生成逻辑
- [ ] 对比官方示例的差异
- [ ] 识别具体的格式问题

### Phase 3: 实施修复 (优先级: P0)
- [ ] 根据文档修改代码
- [ ] 添加必要的参数
- [ ] 调整 calldata 格式

### Phase 4: 测试验证 (优先级: P0)
- [ ] 重启服务
- [ ] 执行完整的订阅流程
- [ ] 验证交易成功上链
- [ ] 检查交易哈希

---

## 5. 当前代码分析

### 问题代码
```javascript
// 构造合约调用数据
const contractInterface = new ethers.Interface(CONTRACT_ABI);
const calldata = contractInterface.encodeFunctionData('permitAndSubscribe', [
  userAddress,
  identityAddress,
  planId,
  maxAmount,
  deadline,
  nonce,
  intentSignature,
  permitSig.v,
  permitSig.r,
  permitSig.s
]);

// 通过 CDP Server Wallet 发送交易
const txResult = await serverWalletAccount.sendTransaction({
  to: CONTRACT_ADDRESS,
  data: calldata,
  network: 'base-sepolia',
});
```

### 潜在问题
1. `calldata` 格式: ethers.js 生成的是 hex string,CDP SDK 是否接受?
2. `network` 参数: 是否应该是 `'base-sepolia'` 还是其他格式?
3. 缺少参数: 是否需要 `value`, `gasLimit`, `maxFeePerGas` 等?

---

## 6. 研究发现

### 从官方文档获取的信息

**来源**: 
- [Smart Contract Interactions](https://docs.cdp.coinbase.com/server-wallets/v1/introduction/onchain-interactions/smart-contract-interactions)
- [Supported Solidity Types](https://docs.cdp.coinbase.com/server-wallets/v1/introduction/onchain-interactions/supported-solidity-types)
- [Sending Transactions Guide](https://www.mintlify.com/coinbase/cdp-sdk/guides/sending-transactions)

**关键发现**:

1. **Solidity 类型编码规则**:
   - `uint256`: 必须传递为字符串 (e.g., `"123456"`)
   - `bytes`: Hex-encoded string (e.g., `"0x1234abcd"`)
   - `address`: 应该是字符串格式
   - `bool`: Boolean 值

2. **当前代码的问题**:
   ```javascript
   // 当前代码
   const calldata = contractInterface.encodeFunctionData('permitAndSubscribe', [
     userAddress,           // ✅ string
     identityAddress,       // ✅ string
     planId,                // ❌ number (应该是 string)
     maxAmount,             // ❌ string (但可能需要 BigInt)
     deadline,              // ❌ number (应该是 string)
     nonce,                 // ❌ string (但可能需要 BigInt)
     intentSignature,       // ✅ string
     permitSig.v,           // ❌ number (应该是 uint8)
     permitSig.r,           // ✅ string
     permitSig.s            // ✅ string
   ]);
   ```

3. **可能的解决方案**:
   - 不使用 `ethers.Interface.encodeFunctionData()`
   - 直接使用 CDP SDK 的合约调用方法
   - 或者确保所有参数都是正确的类型

### 需要进一步研究

- [ ] CDP SDK 是否有专门的合约调用方法?
- [ ] 是否需要使用 CDP SDK 的 Contract 对象而不是直接发送 calldata?
- [ ] 查找 CDP SDK 的 GitHub 仓库中的示例代码

## 8. 最新研究发现 (2026-04-11 17:21)

### 关键发现

根据官方文档搜索,我发现了以下重要信息:

**来源**:
- [Sending Transactions with Server Wallets](https://docs.cdp.coinbase.com/server-wallets/v2/evm-features/sending-transactions)
- [REST API Reference](https://docs.cdp.coinbase.com/api-reference/v2/rest-api/evm-accounts/send-a-transaction)
- [Sending Transactions Guide](https://www.mintlify.com/coinbase/cdp-sdk/guides/sending-transactions)

### 问题根源

1. **我可能使用了错误的 API 方法**:
   - 当前代码使用 `serverWalletAccount.sendTransaction()`
   - 但搜索结果显示这可能不是 CDP SDK 的正确方法

2. **需要验证的问题**:
   - CDP SDK 的 `EvmServerAccount` 对象是否有 `sendTransaction` 方法?
   - 正确的方法名是什么?
   - 参数格式是什么?

### 下一步行动

**立即执行**:
1. ✅ 查阅 CDP Server Wallet 官方文档
2. ✅ 搜索 CDP SDK 的 TypeScript 示例
3. ⏳ 查看 CDP SDK 的源码或 TypeScript 类型定义
4. ⏳ 找到 `EvmServerAccount` 的正确 API

**具体任务**:
- [ ] 检查 `node_modules/@coinbase/cdp-sdk` 的类型定义
- [ ] 查找 `EvmServerAccount` 类的方法列表
- [ ] 确定正确的交易发送方法
- [ ] 修复代码

## 9. 执行计划更新

### Phase 1: 验证 API 方法 (优先级: P0)
- [ ] 检查 CDP SDK 的 TypeScript 类型定义
- [ ] 查找 `EvmServerAccount` 的正确方法
- [ ] 确认 `sendTransaction` 是否存在

### Phase 2: 修复代码 (优先级: P0)
- [ ] 根据正确的 API 修改代码
- [ ] 调整参数格式
- [ ] 测试交易发送

### Phase 3: 验证 (优先级: P0)
- [ ] 重启服务
- [ ] 执行完整的订阅流程
- [ ] 验证交易成功上链

---

## 7. 参考资料

### 官方文档
- [CDP Server Wallets Introduction](https://docs.cdp.coinbase.com/server-wallets/v2/introduction/welcome)
- [Sending Transactions](https://docs.cdp.coinbase.com/server-wallets/v2/evm-features/sending-transactions)
- [CDP SDK Guide](https://mintlify.wiki/coinbase/cdp-sdk/guides/sending-transactions)

### 相关代码
- 文件: `subscription-service/index.js`
- 行号: 221-310 (订阅接口实现)
- 问题行: 284 (sendTransaction 调用)

---

**更新日志**:
- 2026-04-11 17:18: 创建文档,开始问题诊断
