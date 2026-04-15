# 简化订阅方案：EIP-2612 两步签名自动续费

> **文档版本**: v2.1  
> **完成日期**: 2026-04-15  
> **核心结论**: 采用 EIP-2612 无限额授权方案，用户订阅时签名 2 次，此后自动续费无需任何操作

---

## 一、方案演进历史

### 1.1 原始方案（v1.0）

**文档**: `blockchain_subscription_ultimate_solution.md`

**核心技术**: EIP-3009 `transferWithAuthorization` + bytes32 随机 nonce

**实现方式**:
- 用户订阅时签名 **13 次**（1 次主订阅 + 12 次 EIP-3009 续费授权）
- 后端存储 12 个 EIP-3009 签名
- 每月自动续费时，后端调用 `renewWithAuthorization` 提交对应签名
- 完全零 gas（CDP Paymaster 赞助）

**优点**:
- ✅ 零 gas
- ✅ bytes32 随机 nonce，不会因用户其他 USDC 操作而失效
- ✅ 每个签名独立有效，可并发
- ✅ 符合 Circle/CDP 推荐的最佳实践

**缺点**:
- ❌ 用户需要签名 13 次（体验极差）
- ❌ 12 次授权仅覆盖 12 个月，第 13 个月起续费失败，仍需用户重新操作
- ❌ 后端需要存储和管理 12 个签名，有泄漏风险
- ❌ 实现复杂度高

### 1.2 当前实现问题（v1.x 混合状态）

**实际情况**:
1. 前端生成了 12 个 EIP-3009 签名 ✅
2. 合约有 `renewWithAuthorization` 函数支持 EIP-3009 ✅
3. 后端 ❌ **从未存储和使用这些签名**
4. 后端实际使用的是 `executeRenewal`（依赖 EIP-2612 allowance）

**结果**:
- 用户签名了 13 次（1 次主订阅 + 12 次 EIP-3009）
- 12 个 EIP-3009 签名完全没用
- 实际续费依赖的是 EIP-2612 allowance
- **混合了两种方案，导致用户签名次数最多、收益最少**

### 1.3 v2.1 修正说明

v2.0 文档存在以下问题，本版本予以修正：

1. **签名次数描述有误**：文档标题和对比表声称"1 次签名"，但前端代码实际执行 2 次 `signTypedData`，前后矛盾。
2. **授权额度策略有漏洞**：将 `maxAmount` 设为 12 个月总额，意味着 12 个月后 allowance 耗尽，自动续费中断，等同于将问题推迟了 12 个月。
3. **subscriptionList 来源未说明**：定时任务依赖的订阅列表维护机制未定义，存在链上/链下状态不一致风险。
4. **取消订阅后 allowance 残留未说明**：需引导用户主动 revoke。

---

## 二、新方案设计（v2.1）

### 2.1 核心思路

**采用 EIP-2612 permit 无限额授权 + executeRenewal 自动续费**

**关键决策**：

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 授权标准 | EIP-2612 permit | 免 gas，Base USDC 原生支持 |
| 授权额度 | `type(uint256).max`（无限额） | 避免 N 个月后 allowance 耗尽导致续费中断；安全边界由合约层控制，每次只扣 `lockedPrice` |
| Gas 赞助 | CDP Paymaster | 用户零 gas |
| 订阅列表维护 | 监听链上 `Subscribed` 事件 | 唯一可靠来源，防止链下数据库与链上状态不一致 |

### 2.2 EIP-2612 Allowance 风险澄清

**常见误解**: "用户在其他地方转 USDC 会消耗 allowance"

**实际情况**:
```solidity
// USDC 合约的 allowances 映射
mapping(address => mapping(address => uint256)) public allowances;

// 用户授权给合约的 allowance（无限额）
allowances[userAddress][contractAddress] = type(uint256).max

// 用户在其他地方转 USDC（如转给朋友）
usdc.transfer(friendAddress, 1e6)
// ✅ 不会影响 allowances[userAddress][contractAddress]

// 用户在 Uniswap 等 DEX 换 USDC
usdc.transferFrom(userAddress, uniswapRouter, amount)
// ⚠️ 这会消耗 allowances[userAddress][uniswapRouter]
//    但不会影响 allowances[userAddress][contractAddress]
//    因为 spender 不同

// 只有我们的合约调用 transferFrom 才会消耗我们的 allowance
usdc.transferFrom(userAddress, serviceWallet, lockedPrice)
// ✅ 这才会减少 allowances[userAddress][contractAddress]
```

**无限额授权的安全边界**：
- allowance 再大，合约每次调用 `executeRenewal` 也只扣 `lockedPrice`（订阅时写入合约的锁定金额）
- 合约代码是公开可审计的，不存在"多扣"的可能
- 用户可随时调用 `cancelFor` 关闭自动续费；取消后调度器不再触发 `executeRenewal`
- 用户可随时去 USDC 合约直接 `approve(contractAddress, 0)` 撤销授权

**结论**: 无限额授权风险可控，每次实际扣款由合约逻辑严格限定。

### 2.3 技术方案对比

| 维度 | v1.0 EIP-3009 | v2.1 EIP-2612 |
|------|---------------|---------------|
| **用户签名次数** | 13 次 | **2 次** |
| **Gas 费用** | 0（CDP Paymaster） | 0（CDP Paymaster） |
| **授权有效期** | 12 个月 | **永久**（直到主动取消） |
| **实现复杂度** | 高 | **低** |
| **后端存储签名** | 需存储 12 个 | **无需** |
| **Allowance 风险** | 无 | 极低（合约层限额） |
| **年付优惠支持** | ✅ | ✅ |
| **可取消性** | ✅ | ✅ |

---

## 三、实现方案

### 3.1 架构图

```
用户首次订阅
    │
    ▼
前端：用户连续签名 2 次（MetaMask 弹出 2 次弹窗）
    │
    ├─► 签名 1：SubscribeIntent（订阅意图，防重放）
    └─► 签名 2：EIP-2612 Permit（授权无限额 USDC 给合约）
    │
    ▼
后端：CDP Paymaster 赞助 gas，调用 permitAndSubscribe
    │
    ▼
合约：
    ├─► 验证 SubscribeIntent 签名（防止参数篡改）
    ├─► 执行 EIP-2612 permit（写入 type(uint256).max allowance）
    ├─► transferFrom 扣款第一期费用
    └─► 写入订阅（lockedPrice, lockedPeriod, autoRenewEnabled=true）
        并 emit Subscribed(identityAddress, user, planId, expiresAt)
    │
    ▼
后端事件监听器（长期运行）
    监听 Subscribed 事件 → 维护 subscriptionList
    监听 SubscriptionCancelled 事件 → 从 subscriptionList 移除
    │
    ▼
后端定时任务（每 60 秒检查一次）
    │
    ▼
遍历 subscriptionList，发现到期且 autoRenewEnabled=true 的订阅
    │
    ▼
后端调用 executeRenewal（CDP Paymaster 赞助 gas）
    │
    ▼
合约：
    ├─► 检查 autoRenewEnabled == true
    ├─► 检查 allowance >= lockedPrice（不足则 revert，emit RenewalFailed）
    ├─► transferFrom 扣款 lockedPrice
    └─► expiresAt += lockedPeriod
```

### 3.2 前端实现

**订阅流程（2 次签名）**：

```javascript
async function subscribe() {
  const planId = parseInt(document.getElementById('plan').value);
  const identityAddress = document.getElementById('identity').value.trim();
  const isYearly = document.getElementById('isYearly').checked;

  // 1. 获取套餐信息
  const plan = availablePlans.find(p => p.planId === planId);
  const price = isYearly ? plan.pricePerYear : plan.pricePerMonth;

  // 2. 授权额度：无限额
  //    安全边界由合约 executeRenewal 保证，每次只扣 lockedPrice
  const maxAmount = ethers.MaxUint256.toString();

  // 3. 获取 nonce 和 deadline
  const nonceRes = await fetch(`${CONFIG.API_BASE}/intent-nonce?address=${userAddress}`);
  const nonce = (await nonceRes.json()).nonce;
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // 4. 第 1 次签名：SubscribeIntent（订阅意图，防止后端篡改参数）
  const domain = {
    name: 'VPNSubscription',
    version: '2',
    chainId: CONFIG.CHAIN_ID,
    verifyingContract: CONFIG.CONTRACT_ADDRESS,
  };
  const types = {
    SubscribeIntent: [
      { name: 'user',            type: 'address' },
      { name: 'identityAddress', type: 'address' },
      { name: 'planId',          type: 'uint256' },
      { name: 'isYearly',        type: 'bool'    },
      { name: 'maxAmount',       type: 'uint256' },
      { name: 'deadline',        type: 'uint256' },
      { name: 'nonce',           type: 'uint256' },
    ],
  };
  const intentValue = {
    user: userAddress,
    identityAddress,
    planId,
    isYearly,
    maxAmount,
    deadline,
    nonce: parseInt(nonce),
  };

  showStatus('第 1/2 步：签名订阅意图...', 'info');
  const intentSignature = await signer.signTypedData(domain, types, intentValue);

  // 5. 第 2 次签名：EIP-2612 Permit（授权无限额 USDC）
  showStatus('第 2/2 步：签名 USDC 授权（此后自动续费无需再次操作）...', 'info');
  const usdcName = CONFIG.CHAIN_ID === 84532 ? 'USDC' : 'USD Coin';
  const usdcDomain = {
    name: usdcName,
    version: '2',
    chainId: CONFIG.CHAIN_ID,
    verifyingContract: CONFIG.USDC_ADDRESS,
  };
  const permitTypes = {
    Permit: [
      { name: 'owner',   type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value',   type: 'uint256' },
      { name: 'nonce',   type: 'uint256' },
      { name: 'deadline',type: 'uint256' },
    ],
  };
  const usdc = new ethers.Contract(
    CONFIG.USDC_ADDRESS,
    ['function nonces(address) view returns (uint256)'],
    provider
  );
  const usdcNonce = await usdc.nonces(userAddress);
  const permitValue = {
    owner:   userAddress,
    spender: CONFIG.CONTRACT_ADDRESS,
    value:   maxAmount,          // type(uint256).max
    nonce:   usdcNonce,
    deadline,
  };
  const permitSignature = await signer.signTypedData(usdcDomain, permitTypes, permitValue);

  // 6. 提交到后端（后端通过 CDP Paymaster 赞助 gas，用户无需持有 ETH）
  showStatus('提交订阅交易...', 'info');
  const response = await fetch(`${CONFIG.API_BASE}/subscription/subscribe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      userAddress,
      planId,
      identityAddress,
      isYearly,
      intentSignature,
      permitSignature,
      maxAmount,
      deadline,
      nonce,
    }),
  });

  if (!response.ok) throw new Error((await response.json()).error);

  showStatus('订阅成功！后续费用将自动从您的钱包扣除，无需任何操作。', 'success');
  setTimeout(refresh, 2000);
}

// 取消订阅时提示用户同时撤销 allowance
async function cancelSubscription(identityAddress) {
  // ... 调用 cancelFor ...

  // 取消成功后提示
  showStatus(
    '订阅已取消。如需彻底撤销 USDC 授权，请访问 revoke.cash 或在钱包中将合约授权归零。',
    'info'
  );
}
```

**关键变更**：
- 签名次数：保持 2 次（SubscribeIntent + EIP-2612 Permit），不再声称"1 次"
- `maxAmount` 改为 `ethers.MaxUint256`，彻底解决 12 个月后续费中断问题
- UI 文案区分两步，让用户理解每次弹窗的用途
- 取消订阅后引导用户主动 revoke allowance

### 3.3 后端实现

**订阅接口**（无变化）：

```javascript
app.post('/api/subscription/subscribe', async (req, res) => {
  try {
    const {
      userAddress, planId, identityAddress, isYearly,
      intentSignature, permitSignature, maxAmount, deadline, nonce,
    } = req.body;

    // 验证 SubscribeIntent 签名（防止参数被中间人篡改）
    const subscribeMessage = {
      user:            userAddress,
      identityAddress: identityAddress,
      planId:          BigInt(planId),
      isYearly:        Boolean(isYearly),
      maxAmount:       BigInt(maxAmount),
      deadline:        BigInt(deadline),
      nonce:           BigInt(nonce),
    };
    const recoveredAddress = ethers.verifyTypedData(
      DOMAIN, SUBSCRIBE_INTENT_TYPES, subscribeMessage, intentSignature
    );
    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid SubscribeIntent signature' });
    }

    const permitSig = ethers.Signature.from(permitSignature);
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('permitAndSubscribe', [
      userAddress, identityAddress, planId, isYearly,
      maxAmount, deadline, nonce, intentSignature,
      permitSig.v, permitSig.r, permitSig.s,
    ]);

    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount,
      network: 'base-sepolia',
      calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: serverWalletAccount.address,
      userOpHash: userOp.userOpHash,
    });

    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed: ${receipt.status}`);
    }

    res.json({ success: true, transactionHash: receipt.transactionHash });

  } catch (error) {
    console.error('订阅失败:', error);
    res.status(500).json({ error: error.message });
  }
});
```

**订阅列表维护（事件驱动，替代手工维护）**：

```javascript
// ✅ 正确做法：监听链上事件，作为唯一可信来源
//    解决了原方案中 subscriptionList 来源不明的问题

const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

// 监听新增订阅
contract.on('Subscribed', (identityAddress, user, planId, expiresAt) => {
  console.log(`新订阅: ${identityAddress}`);
  subscriptionSet.add(identityAddress);
  db.upsertSubscription({ identityAddress, user, planId, expiresAt });
});

// 监听取消订阅
contract.on('SubscriptionCancelled', (identityAddress) => {
  console.log(`订阅取消: ${identityAddress}`);
  subscriptionSet.delete(identityAddress);
  db.markCancelled(identityAddress);
});

// 监听续费失败（allowance 不足时）
contract.on('RenewalFailed', (identityAddress, reason) => {
  console.error(`续费失败: ${identityAddress}, 原因: ${reason}`);
  notifyUser(identityAddress, 'allowance_insufficient');
});

// 启动时从链上历史事件同步（防止服务重启丢失数据）
async function syncFromChain() {
  const filter = contract.filters.Subscribed();
  const events = await contract.queryFilter(filter, DEPLOY_BLOCK, 'latest');
  for (const event of events) {
    subscriptionSet.add(event.args.identityAddress);
  }
  console.log(`已从链上同步 ${subscriptionSet.size} 个订阅`);
}
```

**自动续费定时任务**：

```javascript
// 每 60 秒检查一次到期订阅
setInterval(async () => {
  const now = Math.floor(Date.now() / 1000);

  for (const identityAddress of subscriptionSet) {
    try {
      const sub = await contract.subscriptions(identityAddress);

      // 跳过：未激活、已关闭自动续费、尚未到期
      if (!sub.isActive || !sub.autoRenewEnabled || now < sub.expiresAt) continue;

      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('executeRenewal', [identityAddress]);

      const userOp = await cdpClient.evm.sendUserOperation({
        smartAccount: serverWalletAccount,
        network: 'base-sepolia',
        calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }],
        paymasterUrl: process.env.CDP_PAYMASTER_URL,
      });

      const receipt = await cdpClient.evm.waitForUserOperation({
        smartAccountAddress: serverWalletAccount.address,
        userOpHash: userOp.userOpHash,
      });

      if (receipt.status === 'complete') {
        console.log(`✅ 自动续费成功: ${identityAddress}`);
      } else {
        console.error(`❌ UserOperation 失败: ${identityAddress}`);
      }

    } catch (error) {
      // executeRenewal revert 时（allowance 不足等），合约会 emit RenewalFailed
      // 由上方事件监听器处理通知逻辑，这里只记录日志
      console.error(`续费异常: ${identityAddress}`, error.message);
    }
  }
}, 60_000);
```

### 3.4 合约实现（无需修改）

合约已完整支持此方案：

1. **`permitAndSubscribe`**: 主订阅入口
   - 验证 SubscribeIntent 签名（防重放，防参数篡改）
   - 执行 EIP-2612 permit（写入 `type(uint256).max` allowance）
   - `transferFrom` 扣款第一期
   - 写入 `lockedPrice`、`lockedPeriod`、`autoRenewEnabled = true`
   - emit `Subscribed`

2. **`executeRenewal`**: 自动续费（由后端 Relayer 调用）
   - 检查 `autoRenewEnabled == true`
   - 检查 `allowance >= lockedPrice`，不足则 emit `RenewalFailed` 并 revert
   - `transferFrom` 扣款 `lockedPrice`
   - `expiresAt += lockedPeriod`

3. **`cancelFor`**: 取消自动续费
   - 设置 `autoRenewEnabled = false`
   - emit `SubscriptionCancelled`
   - **注意**：不自动撤销 USDC allowance（无法跨合约操作），需引导用户手动 revoke

---

## 四、年付优惠支持

### 4.1 价格锁定机制

`lockedPrice` 和 `lockedPeriod` 在首次订阅时写入合约，后续续费始终使用锁定值：

```solidity
// 首次订阅时写入
uint256 price  = isYearly ? plan.pricePerYear  : plan.pricePerMonth;
uint256 period = isYearly ? 365 days           : plan.period;

subscriptions[identityAddress] = Subscription({
    lockedPrice:       uint96(price),
    lockedPeriod:      period,
    autoRenewEnabled:  true,
    // ...
});

// 自动续费时使用锁定值，套餐涨价不影响已有订阅
function executeRenewal(address identityAddress) external {
    Subscription storage sub = subscriptions[identityAddress];
    uint256 price  = uint256(sub.lockedPrice);
    uint256 period = sub.lockedPeriod;
    IERC20(usdc).transferFrom(payer, serviceWallet, price);
    sub.expiresAt += period;
}
```

### 4.2 年付示例

| 阶段 | 操作 |
|------|------|
| 首次订阅（年付） | 用户签名 2 次；合约扣款 10 USDC；锁定价格 10 USDC、周期 365 天 |
| 第 1 年到期 | 后端调用 `executeRenewal`；扣款 10 USDC；延长 365 天；用户无感知 |
| 第 2 年到期 | 同上，allowance 充足（无限额），继续自动续费 |
| 用户取消 | 调用 `cancelFor`；设置 `autoRenewEnabled = false`；后端停止续费 |

---

## 五、方案对比总结

### 5.1 用户体验

| 维度 | v1.0（EIP-3009） | v2.1（EIP-2612） |
|------|-----------------|-----------------|
| 首次签名次数 | 13 次 | **2 次** |
| 此后操作 | 12 个月后需重新授权 | **永不需要** |
| Gas 费用 | 0 | 0 |
| 可取消性 | ✅ | ✅ |
| 年付优惠永久保留 | ✅ | ✅ |

### 5.2 技术实现

| 维度 | v1.0 | v2.1 |
|------|------|------|
| 实现复杂度 | 高 | **低** |
| 后端存储签名 | 需存储 12 个（有泄漏风险） | **无需** |
| 订阅列表维护 | 未定义 | **链上事件驱动** |
| 合约修改 | 需要 | 无需 |
| 前端修改 | 需要 | 需要（移除 EIP-3009 逻辑，修正额度） |

### 5.3 安全性

| 维度 | v1.0 | v2.1 |
|------|------|------|
| 签名存储风险 | 有（后端存 12 个签名） | **无** |
| Allowance 范围 | 无残留 | 无限额，但每次扣款受合约严格限制 |
| 取消后资产安全 | 取消即无授权 | 需用户主动 revoke（已在 UI 引导） |

---

## 六、实施计划

### 6.1 需要修改的文件

| 文件 | 修改内容 |
|------|----------|
| `frontend/app.js` | 1. 移除 `generateEIP3009Signatures` 函数<br>2. `maxAmount` 改为 `ethers.MaxUint256`<br>3. 更新 UI 文案（区分两步签名）<br>4. 取消时提示用户 revoke allowance |
| `subscription-service/index.js` | 1. 移除 `subscriptionList` 手工维护<br>2. 添加链上事件监听（`Subscribed`、`SubscriptionCancelled`、`RenewalFailed`）<br>3. 添加服务启动时的链上历史同步 |
| `contracts/src/VPNSubscriptionV2.sol` | **无需修改** |

### 6.2 实施步骤

1. ✅ 更新设计文档（本文档 v2.1）
2. ⏳ 修改前端：移除 EIP-3009 逻辑，修正 `maxAmount`，更新 UI 文案
3. ⏳ 修改后端：添加事件监听，移除手工列表维护
4. ⏳ 测试订阅流程（含 2 次 MetaMask 弹窗体验）
5. ⏳ 测试自动续费（模拟时间跳过 30 天）
6. ⏳ 测试 12 个月后续费（验证无限额 allowance 不中断）
7. ⏳ 测试取消订阅 + revoke 引导
8. ⏳ 测试年付优惠价格锁定

---

## 七、风险评估

### 7.1 无限额 Allowance 风险

**风险**: 合约如果有漏洞，理论上可以取走用户全部 USDC

**缓解措施**:
- `executeRenewal` 每次只 `transferFrom` `lockedPrice`，金额写死在合约存储中，无法被外部参数影响
- 合约不是可升级合约，逻辑不会被替换
- 建议上线前进行合约审计
- 用户可随时去 USDC 合约调用 `approve(contractAddress, 0)` 完全撤销

**结论**: 风险等级与 Uniswap、Aave 等主流 DeFi 协议要求用户做无限额授权的场景相当，属于行业惯例，可接受。

### 7.2 续费失败风险（用户 USDC 余额不足）

**场景**: 到期时用户钱包 USDC 余额 < `lockedPrice`

**处理**:
- 合约 `executeRenewal` revert，emit `RenewalFailed`
- 后端事件监听器捕获，向用户发送通知（邮件/Push）
- 用户充值后，后端在下一次定时任务中重试（需合约支持重试窗口，建议宽限期 3 天）

### 7.3 取消订阅后 Allowance 残留

**场景**: 用户调用 `cancelFor` 后，USDC allowance 仍然存在

**说明**:
- 合约无法主动撤销 USDC 合约中的 allowance（跨合约操作限制）
- 取消后后端停止调用 `executeRenewal`，allowance 不会被消耗
- 但如果合约将来有漏洞，残留 allowance 仍是风险

**处理**:
- 前端取消成功后，弹出提示引导用户手动 revoke（可提供 revoke.cash 链接或直接调用 USDC `approve(contract, 0)`）
- 这一步为可选操作，但推荐用户执行

### 7.4 服务重启后订阅列表丢失

**场景**: 后端服务重启，内存中的 `subscriptionSet` 清空

**处理**:
- 服务启动时调用 `syncFromChain()`，从合约部署区块开始重建列表
- 同时将列表持久化到本地数据库，作为缓存层，减少启动时的 RPC 查询量

---

## 八、总结

**v2.1 方案采用 EIP-2612 无限额授权 + 链上事件驱动的自动续费**，相比 v1.0：

**优势**:
- ✅ 用户体验大幅提升（2 次签名 vs 13 次，且此后永不需要重新授权）
- ✅ 实现复杂度大幅降低（无签名存储，无管理负担）
- ✅ 完全零 gas（CDP Paymaster 赞助）
- ✅ 订阅列表由链上事件驱动，链上/链下状态强一致
- ✅ 支持年付优惠永久锁定
- ✅ 可随时取消订阅

**风险**:
- ⚠️ 无限额 allowance：每次实际扣款受合约逻辑严格限制，风险等级与主流 DeFi 协议相当
- ⚠️ 取消后 allowance 残留：前端引导用户主动 revoke，已有处理方案

**结论**: v2.1 方案是当前条件下的最优解，修正了 v2.0 的三处设计缺陷，建议按实施计划推进。
