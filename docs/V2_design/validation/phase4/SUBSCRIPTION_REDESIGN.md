# VPN 订阅系统设计修复方案

## 问题描述

当前设计存在严重的业务逻辑错误：一个付款钱包只能有一个订阅。这限制了用户无法为多个 VPN 身份订阅服务。

### 当前错误的设计

```solidity
mapping(address => Subscription) public subscriptions;  // ❌ 一个钱包 → 一个订阅
mapping(address => address) public identityToOwner;     // ✅ 一个身份 → 一个钱包
```

### 正确的业务逻辑

- ✅ 一个付款钱包可以为**多个 VPN 身份**订阅服务
- ✅ 一个 VPN 身份只能有**一个活跃订阅**
- ✅ 就像支付宝可以订阅音乐、读书等多个服务

---

## 修改方案

### 1. 智能合约修改

#### 1.1 修改存储结构

**文件**: `docs/V2_design/validation/phase4/contracts/src/VPNSubscription.sol`

**修改前**:
```solidity
mapping(address => Subscription) public subscriptions;
mapping(address => address) public identityToOwner;
```

**修改后**:
```solidity
// 一个 VPN 身份 → 一个订阅（核心索引）
mapping(address => Subscription) public subscriptions;

// 一个 VPN 身份 → 付款钱包（防止身份被多个钱包绑定）
mapping(address => address) public identityToOwner;

// 一个付款钱包 → 所有订阅的 VPN 身份列表（用于查询）
mapping(address => address[]) public userIdentities;
```

#### 1.2 修改订阅函数

**修改点**: `permitAndSubscribe` 函数

**修改前**:
```solidity
require(!subscriptions[user].isActive, "VPN: already subscribed");
```

**修改后**:
```solidity
// 检查 VPN 身份是否已有订阅（而不是检查付款钱包）
require(!subscriptions[identityAddress].isActive, "VPN: identity already subscribed");
require(identityToOwner[identityAddress] == address(0), "VPN: identity already bound");
```

**完整修改**:
```solidity
function permitAndSubscribe(
    address user,
    address identityAddress,
    uint256 planId,
    uint256 maxAmount,
    uint256 permitDeadline,
    uint256 intentNonce,
    bytes calldata intentSignature,
    uint8 v, bytes32 r, bytes32 s
) external onlyRelayer whenNotPaused {
    Plan memory plan = plans[planId];
    require(plan.isActive, "VPN: plan not available");
    
    // ✅ 修改：检查 VPN 身份是否已有订阅（而不是检查付款钱包）
    require(!subscriptions[identityAddress].isActive, "VPN: identity already subscribed");
    require(maxAmount >= plan.price, "VPN: maxAmount too low");
    require(plan.price <= type(uint96).max, "VPN: price overflow");
    require(identityToOwner[identityAddress] == address(0), "VPN: identity already bound");

    // ... EIP-712 验签 ...

    // ✅ 修改：以 VPN 身份为 key 存储订阅
    identityToOwner[identityAddress] = user;
    subscriptions[identityAddress] = Subscription({
        identityAddress:  identityAddress,
        payerAddress:     user,  // ✅ 新增：记录付款钱包
        lockedPrice:      uint96(plan.price),
        planId:           planId,
        lockedPeriod:     plan.period,
        startTime:        block.timestamp,
        expiresAt:        block.timestamp + plan.period,
        autoRenewEnabled: true,
        isActive:         true
    });

    // ✅ 新增：将身份添加到用户的身份列表
    userIdentities[user].push(identityAddress);

    emit SubscriptionCreated(user, identityAddress, planId, plan.price, plan.period);
}
```

#### 1.3 修改 Subscription 结构体

**修改前**:
```solidity
struct Subscription {
    address identityAddress;
    uint96  lockedPrice;
    uint256 planId;
    uint256 lockedPeriod;
    uint256 startTime;
    uint256 expiresAt;
    bool    autoRenewEnabled;
    bool    isActive;
}
```

**修改后**:
```solidity
struct Subscription {
    address identityAddress;   // VPN 身份地址
    address payerAddress;      // ✅ 新增：付款钱包地址
    uint96  lockedPrice;
    uint256 planId;
    uint256 lockedPeriod;
    uint256 startTime;
    uint256 expiresAt;
    bool    autoRenewEnabled;
    bool    isActive;
}
```

#### 1.4 修改续费函数

**修改点**: `executeRenewal` 函数

**修改前**:
```solidity
function executeRenewal(address user) external onlyRelayer whenNotPaused {
    Subscription storage sub = subscriptions[user];
    // ...
}
```

**修改后**:
```solidity
function executeRenewal(address identityAddress) external onlyRelayer whenNotPaused {
    Subscription storage sub = subscriptions[identityAddress];
    require(sub.isActive, "VPN: not active");
    require(block.timestamp >= sub.expiresAt, "VPN: not yet expired");
    require(sub.autoRenewEnabled, "VPN: auto-renew disabled");

    Plan memory plan = plans[sub.planId];
    require(plan.isActive, "VPN: plan not available");

    // ✅ 修改：从付款钱包扣款（而不是从 identityAddress）
    address payer = sub.payerAddress;
    require(
        IERC20(address(usdc)).transferFrom(payer, serviceWallet, plan.price),
        "VPN: transfer failed"
    );

    sub.expiresAt = block.timestamp + plan.period;
    emit SubscriptionRenewed(payer, identityAddress, plan.price);
}
```

#### 1.5 修改取消订阅函数

**修改点**: `permitAndCancel` 函数

**修改前**:
```solidity
function permitAndCancel(
    address user,
    uint256 cancelNonce,
    bytes calldata cancelSignature
) external onlyRelayer whenNotPaused {
    Subscription storage sub = subscriptions[user];
    // ...
}
```

**修改后**:
```solidity
function permitAndCancel(
    address user,
    address identityAddress,
    uint256 cancelNonce,
    bytes calldata cancelSignature
) external onlyRelayer whenNotPaused {
    // ✅ 修改：以 VPN 身份为 key 查询订阅
    Subscription storage sub = subscriptions[identityAddress];
    require(sub.isActive, "VPN: not active");
    require(sub.payerAddress == user, "VPN: not owner");  // ✅ 验证付款钱包
    require(sub.autoRenewEnabled, "VPN: already cancelled");

    // ... EIP-712 验签 ...

    sub.isActive = false;
    sub.autoRenewEnabled = false;
    identityToOwner[identityAddress] = address(0);

    // ✅ 新增：从用户的身份列表中移除
    _removeIdentityFromUser(user, identityAddress);

    emit SubscriptionCancelled(user, identityAddress);
}
```

#### 1.6 新增辅助函数

```solidity
/**
 * 从用户的身份列表中移除指定身份
 */
function _removeIdentityFromUser(address user, address identityAddress) private {
    address[] storage identities = userIdentities[user];
    for (uint256 i = 0; i < identities.length; i++) {
        if (identities[i] == identityAddress) {
            identities[i] = identities[identities.length - 1];
            identities.pop();
            break;
        }
    }
}

/**
 * 查询用户的所有订阅身份
 */
function getUserIdentities(address user) external view returns (address[] memory) {
    return userIdentities[user];
}

/**
 * 查询用户的所有活跃订阅
 */
function getUserActiveSubscriptions(address user) external view returns (Subscription[] memory) {
    address[] memory identities = userIdentities[user];
    uint256 activeCount = 0;
    
    // 统计活跃订阅数量
    for (uint256 i = 0; i < identities.length; i++) {
        if (subscriptions[identities[i]].isActive) {
            activeCount++;
        }
    }
    
    // 构建活跃订阅数组
    Subscription[] memory activeSubscriptions = new Subscription[](activeCount);
    uint256 index = 0;
    for (uint256 i = 0; i < identities.length; i++) {
        if (subscriptions[identities[i]].isActive) {
            activeSubscriptions[index] = subscriptions[identities[i]];
            index++;
        }
    }
    
    return activeSubscriptions;
}
```

---

### 2. 后端 API 修改

#### 2.1 修改订阅 API

**文件**: `docs/V2_design/validation/phase4/subscription-service/index.js`

**修改点**: `/api/subscription/subscribe` 端点

**修改前**:
```javascript
// 查询链上订阅状态
const subscription = await contract.subscriptions(userAddress);
```

**修改后**:
```javascript
// ✅ 修改：查询 VPN 身份的订阅状态（而不是付款钱包）
const subscription = await contract.subscriptions(identityAddress);

// ✅ 新增：验证身份是否已被绑定
const owner = await contract.identityToOwner(identityAddress);
if (owner !== ethers.ZeroAddress) {
  return res.status(400).json({ 
    error: 'VPN identity already subscribed',
    detail: `This VPN identity is already bound to wallet ${owner}`
  });
}
```

#### 2.2 修改查询订阅 API

**文件**: `docs/V2_design/validation/phase4/subscription-service/index.js`

**修改点**: `/api/subscription/:address` 端点

**修改前**:
```javascript
app.get('/api/subscription/:address', async (req, res) => {
  const { address } = req.params;
  const subscription = await contract.subscriptions(address);
  // ...
});
```

**修改后**:
```javascript
// ✅ 新增：查询用户的所有订阅
app.get('/api/subscriptions/user/:address', async (req, res) => {
  try {
    const { address } = req.params;
    
    if (!ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    
    // 查询用户的所有订阅身份
    const identities = await contract.getUserIdentities(address);
    
    // 查询每个身份的订阅详情
    const subscriptions = [];
    for (const identity of identities) {
      const sub = await contract.subscriptions(identity);
      if (sub[7]) {  // isActive
        subscriptions.push({
          identityAddress: sub[0],
          payerAddress: sub[1],
          lockedPrice: sub[2].toString(),
          planId: Number(sub[3]),
          lockedPeriod: sub[4].toString(),
          startTime: sub[5].toString(),
          expiresAt: sub[6].toString(),
          autoRenewEnabled: sub[7],
          isActive: sub[8],
        });
      }
    }

    res.json({ subscriptions });
  } catch (error) {
    console.error('查询用户订阅失败:', error);
    res.status(500).json({ error: 'Query failed', detail: error.message });
  }
});

// ✅ 保留：查询单个 VPN 身份的订阅
app.get('/api/subscription/identity/:address', async (req, res) => {
  try {
    const { address } = req.params;
    
    if (!ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const subscription = await contract.subscriptions(address);

    const startTime = Number(subscription[5]);
    const hasSubscription = startTime > 0;

    res.json({
      subscription: hasSubscription ? {
        identityAddress: subscription[0],
        payerAddress: subscription[1],
        lockedPrice: subscription[2].toString(),
        planId: Number(subscription[3]),
        lockedPeriod: subscription[4].toString(),
        startTime: subscription[5].toString(),
        expiresAt: subscription[6].toString(),
        autoRenewEnabled: subscription[7],
        isActive: subscription[8],
      } : null
    });
  } catch (error) {
    console.error('查询订阅失败:', error);
    res.status(500).json({ error: 'Query failed', detail: error.message });
  }
});
```

#### 2.3 修改自动续费服务

**文件**: `docs/V2_design/validation/phase4/subscription-service/renewal-service.js`

**修改点**: `checkSubscription` 函数

**修改前**:
```javascript
async checkSubscription(userAddress) {
  const subscription = await contract.subscriptions(userAddress);
  // ...
}
```

**修改后**:
```javascript
async checkSubscription(userAddress) {
  try {
    // ✅ 修改：查询用户的所有订阅身份
    const identities = await contract.getUserIdentities(userAddress);
    
    if (identities.length === 0) {
      console.log(`  [${userAddress}] 没有订阅`);
      return;
    }

    // ✅ 修改：检查每个身份的订阅状态
    for (const identityAddress of identities) {
      const subscription = await contract.subscriptions(identityAddress);
      
      const expiresAt = Number(subscription[6]);
      const autoRenewEnabled = subscription[7];
      const isActive = subscription[8];

      if (!isActive) {
        console.log(`  [${identityAddress}] 订阅未激活,跳过`);
        continue;
      }

      if (!autoRenewEnabled) {
        console.log(`  [${identityAddress}] 自动续费已关闭,跳过`);
        continue;
      }

      const now = Math.floor(Date.now() / 1000);
      const timeUntilExpiry = expiresAt - now;
      const precheckSeconds = this.precheckHours * 3600;

      // 阶段一: 到期前预检
      if (timeUntilExpiry > 0 && timeUntilExpiry <= precheckSeconds) {
        await this.precheckSubscription(identityAddress, subscription);
      }

      // 阶段二: 已到期,执行续费
      if (timeUntilExpiry <= 0) {
        await this.renewSubscription(identityAddress, subscription);
      }
    }
  } catch (error) {
    console.error(`  [${userAddress}] 检查失败:`, error.message);
  }
}
```

**修改点**: `renewSubscription` 函数

**修改前**:
```javascript
async renewSubscription(userAddress, subscription) {
  const calldata = iface.encodeFunctionData('executeRenewal', [userAddress]);
  // ...
}
```

**修改后**:
```javascript
async renewSubscription(identityAddress, subscription) {
  console.log(`  [${identityAddress}] 🔄 执行续费...`);

  const subData = this.subscriptions.get(identityAddress) || { failCount: 0 };

  // 检查失败次数
  if (subData.failCount >= this.maxRenewalFails) {
    console.log(`  [${identityAddress}] ❌ 失败次数已达上限 (${subData.failCount}),执行强制停服`);
    await this.forceCloseSubscription(identityAddress);
    return;
  }

  try {
    // ✅ 修改：传递 VPN 身份地址（而不是付款钱包地址）
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('executeRenewal', [identityAddress]);

    // 通过 CDP Smart Account 发送 UserOperation (0 gas)
    console.log(`  [${identityAddress}] 📤 发送 UserOperation (Paymaster 赞助 gas)...`);
    const userOp = await this.cdpClient.evm.sendUserOperation({
      smartAccount: this.serverWalletAccount,
      network: 'base-sepolia',
      calls: [{
        to: this.contractAddress,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    console.log(`  [${identityAddress}] ⏳ 等待 UserOperation 确认...`);
    const receipt = await this.cdpClient.evm.waitForUserOperation({
      smartAccountAddress: this.serverWalletAccount.address,
      userOpHash: userOp.userOpHash,
    });

    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed: ${receipt.status}`);
    }

    console.log(`  [${identityAddress}] ✅ 续费成功! TX: ${receipt.transactionHash}`);

    // 重置失败计数
    subData.failCount = 0;
    subData.lastRenewalAt = Date.now();
    this.subscriptions.set(identityAddress, subData);

  } catch (error) {
    console.error(`  [${identityAddress}] ❌ 续费失败:`, error.message);

    // 增加失败计数
    subData.failCount = (subData.failCount || 0) + 1;
    this.subscriptions.set(identityAddress, subData);
    console.log(`  [${identityAddress}] 失败次数: ${subData.failCount}/${this.maxRenewalFails}`);
  }
}
```

---

### 3. 前端修改

#### 3.1 修改订阅状态显示

**文件**: `docs/V2_design/validation/phase4/frontend/app.js`

**修改点**: `loadSubscription` 函数

**修改前**:
```javascript
async function loadSubscription() {
  const response = await fetch(`${CONFIG.API_BASE}/subscription/${userAddress}`);
  const data = await response.json();
  // 显示单个订阅
}
```

**修改后**:
```javascript
async function loadSubscription() {
  try {
    // ✅ 修改：查询用户的所有订阅
    const response = await fetch(`${CONFIG.API_BASE}/subscriptions/user/${userAddress}`);
    const data = await response.json();

    const statusEl = document.getElementById('subStatus');
    
    if (data.subscriptions && data.subscriptions.length > 0) {
      // ✅ 显示所有订阅
      let html = '<h4>您的订阅列表:</h4>';
      
      data.subscriptions.forEach((sub, index) => {
        const expiry = new Date(sub.expiresAt * 1000);
        const isActive = sub.isActive ? '✅ 活跃' : '❌ 已过期';
        const planName = sub.planId === 1 ? '月付' : sub.planId === 2 ? '年付' : '测试套餐';
        
        html += `
          <div style="background: #f5f5f5; padding: 15px; border-radius: 8px; margin: 10px 0;">
            <p><strong>订阅 ${index + 1}</strong></p>
            <p><strong>状态:</strong> ${isActive}</p>
            <p><strong>套餐:</strong> ${planName}</p>
            <p><strong>到期时间:</strong> ${expiry.toLocaleString('zh-CN')}</p>
            <p><strong>VPN 身份:</strong> ${sub.identityAddress}</p>
            <button class="btn" onclick="cancelSubscription('${sub.identityAddress}')">取消此订阅</button>
          </div>
        `;
      });
      
      statusEl.innerHTML = html;
    } else {
      statusEl.innerHTML = '<p style="color: #666;">暂无订阅</p>';
    }
  } catch (error) {
    console.error('加载订阅失败:', error);
    document.getElementById('subStatus').textContent = '加载失败';
  }
}
```

#### 3.2 修改取消订阅函数

**修改前**:
```javascript
async function cancel() {
  // 取消当前订阅
}
```

**修改后**:
```javascript
async function cancelSubscription(identityAddress) {
  if (!confirm(`确定要取消 VPN 身份 ${identityAddress} 的订阅吗?`)) return;

  const btn = event.target;
  btn.disabled = true;
  btn.textContent = '处理中...';

  try {
    showStatus('取消订阅中...', 'info');

    // ✅ 修改：传递 VPN 身份地址
    const response = await fetch(`${CONFIG.API_BASE}/subscription/cancel`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userAddress,
        identityAddress,  // ✅ 新增参数
        cancelSignature: '...'
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || '取消失败');
    }

    showStatus('取消成功!', 'success');
    
    // 刷新订阅列表
    setTimeout(() => {
      loadBalance();
      loadSubscription();
    }, 2000);

  } catch (error) {
    console.error('取消失败:', error);
    showStatus('取消失败: ' + error.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '取消订阅';
  }
}
```

---

### 4. 合约 ABI 更新

**文件**: `docs/V2_design/validation/phase4/subscription-service/index.js`

**修改点**: `CONTRACT_ABI`

**新增函数**:
```javascript
const CONTRACT_ABI = [
  // ... 现有 ABI ...
  
  // ✅ 新增：查询用户的所有订阅身份
  'function getUserIdentities(address user) view returns (address[])',
  
  // ✅ 新增：查询用户的所有活跃订阅
  'function getUserActiveSubscriptions(address user) view returns (tuple(address identityAddress, address payerAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, bool isActive)[])',
  
  // ✅ 修改：executeRenewal 参数改为 identityAddress
  'function executeRenewal(address identityAddress) external',
  
  // ✅ 修改：permitAndCancel 新增 identityAddress 参数
  'function permitAndCancel(address user, address identityAddress, uint256 cancelNonce, bytes calldata cancelSignature) external',
];
```

---

## 实施步骤（技术验证阶段）

⚠️ **注意**：当前处于技术验证阶段，无需考虑数据迁移。直接部署新合约即可。

### 阶段 1: 合约修改与部署（预计 2-3 天）

#### 1.1 修改合约代码

**文件**: `docs/V2_design/validation/phase4/contracts/src/VPNSubscription.sol`

1. 修改存储结构（添加 `userIdentities` mapping）
2. 修改 `Subscription` 结构体（添加 `payerAddress` 字段）
3. 修改 `permitAndSubscribe` 函数
4. 修改 `executeRenewal` 函数
5. 修改 `permitAndCancel` 函数
6. 添加辅助函数：
   - `_removeIdentityFromUser`
   - `getUserIdentities`
   - `getUserActiveSubscriptions`

#### 1.2 编写测试用例

**文件**: `docs/V2_design/validation/phase4/contracts/test/VPNSubscription.t.sol`

测试用例：
```solidity
// 测试一个钱包订阅多个 VPN 身份
function testMultipleSubscriptions() public {
    address user = address(0x1);
    address identity1 = address(0x2);
    address identity2 = address(0x3);
    
    // 订阅第一个身份
    vm.prank(relayer);
    vpn.permitAndSubscribe(user, identity1, 1, ...);
    
    // 订阅第二个身份
    vm.prank(relayer);
    vpn.permitAndSubscribe(user, identity2, 1, ...);
    
    // 验证两个订阅都存在
    address[] memory identities = vpn.getUserIdentities(user);
    assertEq(identities.length, 2);
    assertTrue(vpn.subscriptions(identity1).isActive);
    assertTrue(vpn.subscriptions(identity2).isActive);
}

// 测试 VPN 身份唯一性
function testIdentityUniqueness() public {
    address user1 = address(0x1);
    address user2 = address(0x2);
    address identity = address(0x3);
    
    // 用户1订阅
    vm.prank(relayer);
    vpn.permitAndSubscribe(user1, identity, 1, ...);
    
    // 用户2尝试订阅同一个身份，应该失败
    vm.prank(relayer);
    vm.expectRevert("VPN: identity already bound");
    vpn.permitAndSubscribe(user2, identity, 1, ...);
}

// 测试自动续费（多订阅场景）
function testRenewalMultipleSubscriptions() public {
    // 测试一个钱包的多个订阅都能正确续费
}

// 测试取消订阅（不影响其他订阅）
function testCancelOneSubscription() public {
    // 测试取消一个订阅不影响其他订阅
}
```

#### 1.3 部署新合约（包含测试套餐）

**文件**: `docs/V2_design/validation/phase4/contracts/script/Deploy.s.sol`

部署脚本应该包含测试套餐的配置：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/VPNSubscription.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address serviceWallet = vm.envAddress("SERVICE_WALLET_ADDRESS");
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        address usdc = vm.envAddress("USDC_CONTRACT");

        vm.startBroadcast(deployerPrivateKey);

        // 部署合约
        VPNSubscription vpn = new VPNSubscription(usdc, serviceWallet, relayer);
        console.log("VPNSubscription deployed at:", address(vpn));

        // 配置套餐
        // Plan 1: 月付套餐 - 5 USDC / 30 天
        vpn.setPlan(1, 5_000000, 30 days, true);
        console.log("Plan 1 (Monthly) configured");

        // Plan 2: 年付套餐 - 50 USDC / 365 天
        vpn.setPlan(2, 50_000000, 365 days, true);
        console.log("Plan 2 (Yearly) configured");

        // ⚠️ Plan 3: 测试套餐 - 0.1 USDC / 30 分钟（仅测试网）
        vpn.setPlan(3, 100000, 30 minutes, true);
        console.log("Plan 3 (Test - 30 min) configured");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Contract:", address(vpn));
        console.log("Service Wallet:", serviceWallet);
        console.log("Relayer:", relayer);
        console.log("USDC:", usdc);
        console.log("\nPlans configured:");
        console.log("  1: Monthly (5 USDC / 30 days)");
        console.log("  2: Yearly (50 USDC / 365 days)");
        console.log("  3: Test (0.1 USDC / 30 min) - TESTNET ONLY");
    }
}
```

**部署步骤**：

```bash
# 1. 编译合约
cd docs/V2_design/validation/phase4/contracts
forge build

# 2. 运行测试
forge test -vvv

# 3. 部署到 Base Sepolia（包含测试套餐）
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --verify

# 4. 记录新合约地址
# 输出示例:
# VPNSubscription deployed at: 0x1234...5678
# Plan 1 (Monthly) configured
# Plan 2 (Yearly) configured
# Plan 3 (Test - 30 min) configured

# 5. 更新 .env 文件
echo "VPN_SUBSCRIPTION_CONTRACT=0x1234...5678" >> ../.env
```

**验证部署**：

```bash
# 验证测试套餐已配置
cast call <NEW_CONTRACT_ADDRESS> "plans(uint256)" 3 \
  --rpc-url https://sepolia.base.org

# 预期输出:
# price: 100000 (0.1 USDC)
# period: 1800 (30 分钟)
# isActive: true
```

⚠️ **重要提示**：
- 测试套餐（planId=3）仅用于测试网验证自动续费功能
- 主网部署时应移除或禁用测试套餐
- 在部署脚本中添加清晰的注释标记测试套餐

#### 1.4 验证合约功能

```bash
# 使用 cast 验证合约函数
cast call <NEW_CONTRACT_ADDRESS> "getUserIdentities(address)" <USER_ADDRESS> \
  --rpc-url https://sepolia.base.org

# 验证套餐配置
cast call <NEW_CONTRACT_ADDRESS> "plans(uint256)" 1 \
  --rpc-url https://sepolia.base.org
```

---

### 阶段 2: CDP 配置修改（预计 1 天）

#### 2.1 更新 CDP Paymaster Policy

⚠️ **重要**：合约地址变更后，必须更新 CDP Paymaster 的白名单配置。

**步骤**：

1. **登录 CDP Portal**
   - 访问 https://portal.cdp.coinbase.com/
   - 使用你的 Coinbase 账号登录

2. **找到 Paymaster Policy**
   - 进入 "Paymaster" 或 "Gas Sponsorship" 页面
   - 找到当前使用的 Policy（应该已经配置了旧合约地址）

3. **更新合约白名单**
   - 点击 "Edit Policy" 或 "Update Whitelist"
   - 添加新合约地址：`<NEW_CONTRACT_ADDRESS>`
   - 可以选择：
     - **方案 A**：同时保留旧合约地址（用于测试对比）
     - **方案 B**：移除旧合约地址，只保留新合约地址
   - 建议先使用方案 A，验证新合约正常工作后再移除旧合约

4. **配置 Gas 限制**
   - 确认 Gas Limit 设置合理（建议 500,000 - 1,000,000）
   - 确认 Policy 的预算充足

5. **保存并验证**
   - 保存配置
   - 等待 1-2 分钟让配置生效
   - 使用测试交易验证 Paymaster 是否正常工作

#### 2.2 更新环境变量

**文件**: `docs/V2_design/validation/phase4/.env`

```bash
# 更新合约地址
VPN_SUBSCRIPTION_CONTRACT=<NEW_CONTRACT_ADDRESS>

# CDP Paymaster URL 保持不变
CDP_PAYMASTER_URL=https://api.developer.coinbase.com/rpc/v1/base-sepolia/NEBYVp2cH4KnkATJnEQ5BD9G38vB0Mk4

# 其他配置保持不变
```

#### 2.3 验证 CDP 配置

创建测试脚本验证 Paymaster 是否正常工作：

**文件**: `docs/V2_design/validation/phase4/test_paymaster.js`

```javascript
require('dotenv').config();
const { CdpClient } = require('@coinbase/cdp-sdk');
const { ethers } = require('ethers');

async function testPaymaster() {
  console.log('🧪 测试 CDP Paymaster 配置...\n');

  // 初始化 CDP Client
  const cdpClient = new CdpClient({
    apiKeyId: process.env.CDP_API_KEY_ID,
    apiKeySecret: process.env.CDP_API_KEY_SECRET,
  });

  // 获取 Smart Account
  const ownerAccount = await cdpClient.evm.getOrCreateAccount({
    name: 'openmesh-vpn-owner',
  });

  const smartAccount = await cdpClient.evm.getOrCreateSmartAccount({
    name: 'openmesh-vpn-smart',
    owner: ownerAccount,
  });

  console.log('✅ Smart Account:', smartAccount.address);

  // 测试发送 UserOperation
  try {
    const iface = new ethers.Interface([
      'function plans(uint256) view returns (uint256 price, uint256 period, bool isActive)'
    ]);
    const calldata = iface.encodeFunctionData('plans', [1]);

    console.log('\n📤 发送测试 UserOperation...');
    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount,
      network: 'base-sepolia',
      calls: [{
        to: process.env.VPN_SUBSCRIPTION_CONTRACT,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    console.log('✅ UserOperation 已提交:', userOp.userOpHash);

    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: smartAccount.address,
      userOpHash: userOp.userOpHash,
    });

    if (receipt.status === 'complete') {
      console.log('✅ Paymaster 配置正常! TX:', receipt.transactionHash);
    } else {
      console.error('❌ UserOperation 失败:', receipt.status);
    }
  } catch (error) {
    console.error('❌ Paymaster 测试失败:', error.message);
    console.error('\n可能的原因:');
    console.error('1. CDP Portal 中未添加新合约地址到白名单');
    console.error('2. Paymaster Policy 预算不足');
    console.error('3. 合约地址配置错误');
  }
}

testPaymaster().catch(console.error);
```

运行测试：
```bash
cd docs/V2_design/validation/phase4
node test_paymaster.js
```

---

### 阶段 3: 后端修改（预计 2-3 天）

#### 3.1 更新合约 ABI

**文件**: `docs/V2_design/validation/phase4/subscription-service/index.js`

```javascript
const CONTRACT_ABI = [
  // ... 现有 ABI ...
  
  // ✅ 新增
  'function getUserIdentities(address user) view returns (address[])',
  'function getUserActiveSubscriptions(address user) view returns (tuple(address identityAddress, address payerAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, bool isActive)[])',
  
  // ✅ 修改
  'function executeRenewal(address identityAddress) external',
  'function permitAndCancel(address user, address identityAddress, uint256 cancelNonce, bytes calldata cancelSignature) external',
];
```

#### 3.2 修改订阅 API

**文件**: `docs/V2_design/validation/phase4/subscription-service/index.js`

修改 `/api/subscription/subscribe` 端点：
- 查询 VPN 身份的订阅状态（而不是付款钱包）
- 验证身份是否已被绑定

#### 3.3 新增查询 API

新增 `/api/subscriptions/user/:address` 端点：
- 查询用户的所有订阅
- 返回订阅列表

保留 `/api/subscription/identity/:address` 端点：
- 查询单个 VPN 身份的订阅

#### 3.4 修改自动续费服务

**文件**: `docs/V2_design/validation/phase4/subscription-service/renewal-service.js`

修改 `checkSubscription` 函数：
- 查询用户的所有订阅身份
- 遍历每个身份，检查是否需要续费

修改 `renewSubscription` 函数：
- 传递 VPN 身份地址（而不是付款钱包地址）

#### 3.5 测试后端 API

```bash
# 1. 重启服务
cd docs/V2_design/validation/phase4/subscription-service
npm install
node index.js

# 2. 测试查询用户的所有订阅
curl http://localhost:3000/api/subscriptions/user/0x490DC2F60aececAFF22BC670166cbb9d5DdB9241

# 3. 测试查询单个身份的订阅
curl http://localhost:3000/api/subscription/identity/0x729e71ff357ccefAa31635931621531082A698f6

# 4. 测试订阅（多个身份）
# 使用前端或 Postman 测试

# 5. 测试自动续费
curl -X POST http://localhost:3000/api/renewal/add \
  -H "Content-Type: application/json" \
  -d '{"userAddress": "0x490DC2F60aececAFF22BC670166cbb9d5DdB9241"}'

curl -X POST http://localhost:3000/api/renewal/trigger
```

---

### 阶段 4: 前端修改（预计 1-2 天）

#### 4.1 更新订阅状态显示

**文件**: `docs/V2_design/validation/phase4/frontend/app.js`

修改 `loadSubscription` 函数：
- 调用新的 API 查询用户的所有订阅
- 显示订阅列表（而不是单个订阅）
- 每个订阅显示独立的"取消订阅"按钮

#### 4.2 修改取消订阅功能

新增 `cancelSubscription(identityAddress)` 函数：
- 接收 VPN 身份地址参数
- 调用后端 API 取消指定身份的订阅

#### 4.3 测试前端交互

```bash
# 1. 启动前端服务
cd docs/V2_design/validation/phase4/frontend
python3 -m http.server 8080

# 2. 在浏览器中测试
# - 连接 MetaMask
# - 订阅多个 VPN 身份
# - 验证订阅列表显示正确
# - 取消其中一个订阅
# - 验证其他订阅不受影响
```

---

### 阶段 5: 集成测试（预计 1 天）

#### 5.1 端到端测试场景

**场景 1：多订阅创建**
1. 用户连接 MetaMask（地址 A）
2. 订阅 VPN 身份 1（0 gas）
3. 订阅 VPN 身份 2（0 gas）
4. 订阅 VPN 身份 3（0 gas）
5. 验证所有订阅都显示在列表中

**场景 2：身份唯一性验证**
1. 用户 A 订阅 VPN 身份 X
2. 用户 B 尝试订阅 VPN 身份 X
3. 验证合约拒绝重复订阅

**场景 3：自动续费（多订阅）**
1. 用户 A 有 3 个订阅（使用测试套餐，30 分钟周期）
2. 等待 20 分钟
3. 验证自动续费服务检测到 3 个即将到期的订阅
4. 等待 30 分钟
5. 验证自动续费服务成功续费所有 3 个订阅

**场景 4：取消订阅（不影响其他订阅）**
1. 用户 A 有 3 个订阅
2. 取消订阅 2
3. 验证订阅 1 和订阅 3 仍然活跃
4. 验证订阅 2 已取消

#### 5.2 性能测试

测试一个钱包订阅 10 个 VPN 身份：
- 查询性能
- Gas 消耗
- 自动续费性能

#### 5.3 错误处理测试

- USDC 余额不足
- 网络错误
- Paymaster 失败
- 合约 revert

---

### 阶段 6: 文档更新（预计 0.5 天）

#### 6.1 更新 API 文档

记录新的 API 端点和参数变化

#### 6.2 更新用户指南

说明如何管理多个订阅

#### 6.3 更新开发者文档

说明合约架构变化和迁移指南

---

## 时间估算

| 阶段 | 预计时间 | 关键里程碑 |
|------|---------|-----------|
| 阶段 1: 合约修改与部署 | 2-3 天 | 新合约部署成功 |
| 阶段 2: CDP 配置修改 | 1 天 | Paymaster 验证通过 |
| 阶段 3: 后端修改 | 2-3 天 | API 测试通过 |
| 阶段 4: 前端修改 | 1-2 天 | UI 测试通过 |
| 阶段 5: 集成测试 | 1 天 | 所有场景测试通过 |
| 阶段 6: 文档更新 | 0.5 天 | 文档完成 |
| **总计** | **7.5-10.5 天** | **系统上线** |

---

## 回滚计划

如果新系统出现问题，可以快速回滚：

1. **合约回滚**：在 CDP Portal 中恢复旧合约地址的白名单
2. **后端回滚**：恢复 `.env` 中的旧合约地址，重启服务
3. **前端回滚**：恢复旧版本的前端代码

⚠️ **注意**：由于是技术验证阶段，无需担心数据迁移问题。如果需要回滚，直接切换回旧合约即可。

---

## 测试计划

### 测试用例

1. **多订阅测试**
   - 一个钱包为 3 个不同的 VPN 身份订阅
   - 验证所有订阅都能正常创建
   - 验证查询 API 返回所有订阅

2. **身份唯一性测试**
   - 尝试用不同钱包订阅同一个 VPN 身份
   - 验证合约拒绝重复订阅

3. **自动续费测试**
   - 一个钱包有多个订阅
   - 验证自动续费服务能正确续费所有订阅

4. **取消订阅测试**
   - 取消其中一个订阅
   - 验证其他订阅不受影响

---

## 风险评估

### 高风险

- ⚠️ **需要重新部署合约**：现有订阅数据需要迁移
- ⚠️ **存储成本增加**：`userIdentities` mapping 会增加 gas 成本

### 中风险

- ⚠️ **API 不兼容**：前端和后端需要同步更新
- ⚠️ **自动续费逻辑复杂度增加**：需要遍历多个订阅

### 低风险

- ✅ 核心业务逻辑更合理
- ✅ 用户体验大幅提升

---

## 总结

这个修改方案彻底解决了"一个钱包只能有一个订阅"的设计 bug，使系统符合真实的业务需求。修改涉及智能合约、后端 API、前端界面和自动续费服务，需要全方位协调实施。

**核心改变**：
- 订阅索引从 `付款钱包 → 订阅` 改为 `VPN 身份 → 订阅`
- 新增 `付款钱包 → VPN 身份列表` 的映射关系
- 所有相关函数参数和逻辑相应调整

---

## 开发验证跟踪表

| 阶段 | 任务 | 状态 | 验证方法 | 备注 |
|------|------|------|---------|------|
| **阶段1** | 修改合约存储结构 | ✅ 已完成 | 编译通过 | 添加 userIdentities mapping |
| | 修改 Subscription 结构体 | ✅ 已完成 | 编译通过 | 添加 payerAddress 字段 |
| | 修改 permitAndSubscribe | ✅ 已完成 | 单元测试 | 检查 VPN 身份而非钱包 |
| | 修改 executeRenewal | ✅ 已完成 | 单元测试 | 参数改为 identityAddress |
| | 修改 permitAndCancel | ✅ 已完成 | 单元测试 | 新增 identityAddress 参数 |
| | 添加辅助函数 | ✅ 已完成 | 单元测试 | getUserIdentities 等 |
| | 编写测试用例 | ⏳ 待开始 | forge test | 多订阅、身份唯一性 |
| | 部署新合约（含测试套餐） | ✅ 已完成 | cast call | 已部署到 Base Sepolia |
| **阶段2** | 更新 CDP Paymaster 白名单 | ✅ 已完成 | test_paymaster.js | 用户已手动完成 |
| | 更新 .env 配置 | ✅ 已完成 | 手动检查 | 新合约地址已更新 |
| **阶段3** | 更新合约 ABI | ✅ 已完成 | 编译通过 | 新增函数签名 |
| | 修改订阅 API | ✅ 已完成 | curl 测试 | 查询 VPN 身份状态 |
| | 新增查询 API | ✅ 已完成 | curl 测试 | /api/subscriptions/user/:address |
| | 修改自动续费服务 | ✅ 已完成 | 日志验证 | 支持多订阅检查 |
| | 更新 EIP-712 Domain | ✅ 已完成 | 签名验证 | version 改为 '2' |
| | 更新 CANCEL_INTENT_TYPES | ✅ 已完成 | 签名验证 | 添加 identityAddress 字段 |
| **阶段4** | 修改前端订阅列表显示 | ✅ 已完成 | 浏览器测试 | 显示多个订阅 |
| | 修改取消订阅功能 | ✅ 已完成 | 浏览器测试 | 独立取消按钮 + 签名流程 |
| | 更新合约地址 | ✅ 已完成 | 配置检查 | V2 合约地址 |
| **阶段5** | 创建测试文档 | ✅ 已完成 | 文档审查 | TESTING_GUIDE.md |
| | 多订阅创建测试 | ⏳ 待开始 | 3个订阅成功 | 场景1 |
| | 身份唯一性测试 | ⏳ 待开始 | 合约拒绝 | 场景2 |
| | 自动续费测试（多订阅） | ⏳ 待开始 | 30分钟验证 | 场景3，使用测试套餐 |
| | 取消订阅测试 | ⏳ 待开始 | 其他订阅不受影响 | 场景4 |
| **阶段6** | 更新文档 | ✅ 已完成 | 文档审查 | 函数签名、实施状态、测试指南 |

**状态说明**：
- ⏳ 待开始
- 🔄 进行中
- ✅ 已完成
- ❌ 失败/阻塞

**当前进度**：21/26 任务完成 (阶段1-4: ✅ 完成，阶段5: 🔄 准备测试，阶段6: ✅ 完成)

**最后更新**：2026-04-13 10:41

**已完成工作**：
- ✅ V2 合约创建完成 (VPNSubscriptionV2.sol)
- ✅ 支持一个钱包为多个 VPN 身份订阅
- ✅ 部署脚本创建完成 (DeployV2.s.sol，包含测试套餐)
- ✅ 合约编译成功
- ✅ 部署到 Base Sepolia: 0x16D6D1564942798720CB69a6814bc2C53ECe23a1
- ✅ .env 配置已更新
- ✅ 函数签名文档已创建 (V2_FUNCTION_SIGNATURES.md)
- ✅ CDP Paymaster 白名单已更新
- ✅ 后端 API 已更新（合约 ABI、查询端点、自动续费服务）
- ✅ EIP-712 Domain version 改为 '2'
- ✅ CANCEL_INTENT_TYPES 添加 identityAddress 字段
- ✅ 前端界面已更新（订阅列表显示、独立取消按钮、签名流程）
- ✅ 测试文档已创建 (TESTING_GUIDE.md)

**下一步**：
- 🔄 按照 TESTING_GUIDE.md 执行集成测试
- ⏳ 验证所有测试场景通过
