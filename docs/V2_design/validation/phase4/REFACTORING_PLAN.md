# VPNSubscriptionV2 合约重构实施计划

## 目标

基于 `FINAL_SMART_CONTRACT_DESIGN.md` 的设计原则，将当前合约重构为极简、稳定、语义清晰的订阅合约。

## 核心原则

1. 合约只保存关键事实，不保存派生状态
2. 订阅状态通过 `expiresAt` 和 `autoRenewEnabled` 推导
3. 不依赖 `finalizeExpired()` 保证正确性
4. 不删除历史订阅数据
5. 过期后可直接覆盖重新订阅
6. 复杂运营逻辑全部下放到服务端

---

## 第一阶段：精简 Subscription 结构体

### 1.1 修改 `Subscription` 结构体

**文件**: `contracts/src/VPNSubscriptionV2.sol`

**当前结构** (16 个字段):
```solidity
struct Subscription {
    address identityAddress;
    address payerAddress;
    uint96  lockedPrice;
    uint256 planId;
    uint256 lockedPeriod;
    uint256 startTime;
    uint256 expiresAt;
    uint256 renewedAt;
    uint256 nextRenewalAt;        // 删除
    bool    autoRenewEnabled;
    uint256 nextPlanId;           // 删除
    uint256 trafficUsedDaily;     // 删除
    uint256 trafficUsedMonthly;   // 删除
    uint256 lastResetDaily;       // 删除
    uint256 lastResetMonthly;     // 删除
    bool    isSuspended;          // 删除
}
```

**最终结构** (9 个字段):
```solidity
struct Subscription {
    address identityAddress;
    address payerAddress;
    uint96  lockedPrice;
    uint256 planId;
    uint256 lockedPeriod;
    uint256 startTime;
    uint256 expiresAt;
    uint256 renewedAt;
    bool    autoRenewEnabled;
}
```

### 1.2 删除状态变量

删除以下状态变量:
```solidity
address[] private activeSubscriptions;
mapping(address => uint256) private activeSubscriptionIndex;
```

保留:
```solidity
mapping(address => Subscription) public subscriptions;
mapping(address => uint256) public intentNonces;
mapping(address => uint256) public cancelNonces;
mapping(address => address[]) public userIdentities;  // 可选保留
```

### 1.3 删除辅助函数

删除以下私有函数:
- `_addToActiveSubscriptions(address)`
- `_removeFromActiveSubscriptions(address)`
- `_applyPendingChange(address)`

---

## 第二阶段：修改核心函数

### 2.1 `permitAndSubscribe()` - 支持过期后重订

**当前问题**:
- 过期后重订被 `identityToOwner` 阻塞
- 依赖 `finalizeExpired()` 清理

**修改方案**:

```solidity
function permitAndSubscribe(
    address user,
    address identityAddress,
    uint256 planId,
    bool isYearly,
    uint256 permitDeadline,
    bytes calldata userSignature,
    bytes calldata permitSignature
) external nonReentrant {
    require(identityAddress != address(0), "VPN: zero identity");
    require(permitDeadline >= block.timestamp, "VPN: permit expired");
    
    Plan storage plan = plans[planId];
    require(plan.isActive, "VPN: plan not active");
    
    // 核心改动：只检查是否过期，不检查 identityToOwner
    Subscription storage sub = subscriptions[identityAddress];
    require(sub.expiresAt <= block.timestamp, "VPN: identity already subscribed");
    
    // 验证签名
    bytes32 intentHash = _hashSubscriptionIntent(user, identityAddress, planId, isYearly, intentNonces[user]);
    address signer = ECDSA.recover(intentHash, userSignature);
    require(signer == user, "VPN: invalid signature");
    intentNonces[user]++;
    
    // 计算价格和周期
    uint256 price = isYearly ? plan.yearlyPrice : plan.monthlyPrice;
    uint256 period = isYearly ? 365 days : 30 days;
    
    // Permit + 扣款
    IERC20Permit(address(paymentToken)).permit(
        user, address(this), price, permitDeadline, 
        uint8(bytes1(permitSignature[64])),
        bytes32(permitSignature[0:32]),
        bytes32(permitSignature[32:64])
    );
    require(paymentToken.transferFrom(user, address(this), price), "VPN: payment failed");
    
    // 写入订阅记录（覆盖旧记录）
    subscriptions[identityAddress] = Subscription({
        identityAddress: identityAddress,
        payerAddress: user,
        lockedPrice: uint96(price),
        planId: planId,
        lockedPeriod: period,
        startTime: block.timestamp,
        expiresAt: block.timestamp + period,
        renewedAt: block.timestamp,
        autoRenewEnabled: true
    });
    
    // 更新 userIdentities（如果是新用户）
    if (userIdentities[user].length == 0 || 
        !_identityExists(user, identityAddress)) {
        userIdentities[user].push(identityAddress);
    }
    
    emit SubscriptionCreated(identityAddress, user, planId, block.timestamp + period);
}
```

**关键改动**:
1. 删除 `identityToOwner` 检查
2. 删除 `_addToActiveSubscriptions()` 调用
3. 允许过期后直接覆盖旧记录
4. 不再写入 `nextRenewalAt`, `nextPlanId`, 流量字段, `isSuspended`

### 2.2 `executeRenewal()` - 简化续费逻辑

**当前问题**:
- 检查 `isSuspended`
- 检查 `nextRenewalAt`
- 调用 `_applyPendingChange()`
- 更新 `nextRenewalAt`

**修改方案**:

```solidity
function executeRenewal(address identityAddress) external nonReentrant {
    Subscription storage sub = subscriptions[identityAddress];
    
    // 简化前置校验
    require(sub.expiresAt > 0, "VPN: not subscribed");
    require(sub.autoRenewEnabled, "VPN: auto renew disabled");
    require(block.timestamp >= sub.expiresAt, "VPN: renewal not due");
    require(block.timestamp <= sub.expiresAt + RENEWAL_GRACE_PERIOD, "VPN: renewal window passed");
    
    // 检查余额和授权
    uint256 allowance = paymentToken.allowance(sub.payerAddress, address(this));
    uint256 balance = paymentToken.balanceOf(sub.payerAddress);
    
    if (allowance < sub.lockedPrice) {
        emit RenewalFailed(identityAddress, sub.payerAddress, "insufficient allowance");
        return;
    }
    
    if (balance < sub.lockedPrice) {
        emit RenewalFailed(identityAddress, sub.payerAddress, "insufficient balance");
        return;
    }
    
    // 扣款
    require(paymentToken.transferFrom(sub.payerAddress, address(this), sub.lockedPrice), 
            "VPN: payment failed");
    
    // 延长到期时间
    uint256 renewalBase = block.timestamp > sub.expiresAt ? block.timestamp : sub.expiresAt;
    sub.renewedAt = block.timestamp;
    sub.expiresAt = renewalBase + sub.lockedPeriod;
    
    emit SubscriptionRenewed(identityAddress, sub.expiresAt);
}
```

**关键改动**:
1. 删除 `isSuspended` 检查
2. 删除 `nextRenewalAt` 检查
3. 删除 `_applyPendingChange()` 调用
4. 删除 `nextRenewalAt` 更新
5. 续费失败不修改任何状态

### 2.3 `cancelSubscription()` / `cancelFor()` - 保持不变

这两个函数已经符合设计原则，只需确保:
```solidity
sub.autoRenewEnabled = false;
```

不修改其他字段。

### 2.4 `upgradeSubscription()` - 保留立即升级

**修改方案**:

```solidity
function upgradeSubscription(
    address user,
    address identityAddress,
    uint256 newPlanId,
    bool isYearly,
    uint256 nonce,
    bytes calldata signature
) external nonReentrant {
    Subscription storage sub = subscriptions[identityAddress];
    
    // 简化校验
    require(sub.expiresAt > block.timestamp, "VPN: subscription expired");
    require(sub.payerAddress == user, "VPN: not owner");
    
    Plan storage newPlan = plans[newPlanId];
    require(newPlan.isActive, "VPN: plan not active");
    require(newPlan.tier > plans[sub.planId].tier, "VPN: not an upgrade");
    
    // 验证签名
    bytes32 upgradeHash = _hashUpgradeIntent(user, identityAddress, newPlanId, isYearly, nonce);
    address signer = ECDSA.recover(upgradeHash, signature);
    require(signer == user, "VPN: invalid signature");
    require(intentNonces[user] == nonce, "VPN: invalid nonce");
    intentNonces[user]++;
    
    // 计算补差价
    uint256 newPrice = isYearly ? newPlan.yearlyPrice : newPlan.monthlyPrice;
    uint256 newPeriod = isYearly ? 365 days : 30 days;
    uint256 prorationRefund = calculateUpgradeProration(identityAddress, newPlanId, isYearly);
    
    // 扣款
    require(paymentToken.transferFrom(user, address(this), prorationRefund), 
            "VPN: payment failed");
    
    // 立即更新套餐
    sub.planId = newPlanId;
    sub.lockedPrice = uint96(newPrice);
    sub.lockedPeriod = newPeriod;
    // expiresAt 不变
    // autoRenewEnabled 不变
    
    emit SubscriptionUpgraded(identityAddress, newPlanId, sub.expiresAt);
}
```

**关键改动**:
1. 删除 `isSuspended` 检查
2. 不恢复 `autoRenewEnabled`（如果用户已取消，升级后仍然是取消状态）

### 2.5 删除以下函数

完全删除:
- `finalizeExpired(address, bool)`
- `downgradeSubscription(...)`
- `cancelPendingChange(...)`
- `getAllActiveSubscriptions()`
- `getActiveSubscriptionCount()`
- `reportTrafficUsage(...)`
- `checkTrafficLimit(...)`
- `suspendForTrafficLimit(...)`
- `resumeAfterReset(...)`
- `resetDailyTraffic(...)`
- `resetMonthlyTraffic(...)`

---

## 第三阶段：修改事件

### 3.1 保留的事件

```solidity
event SubscriptionCreated(address indexed identityAddress, address indexed payer, uint256 planId, uint256 expiresAt);
event SubscriptionRenewed(address indexed identityAddress, uint256 newExpiresAt);
event SubscriptionCancelled(address indexed identityAddress, address indexed payer);
event SubscriptionUpgraded(address indexed identityAddress, uint256 newPlanId, uint256 expiresAt);
event RenewalFailed(address indexed identityAddress, address indexed payer, string reason);
```

### 3.2 删除的事件

```solidity
event SubscriptionExpired(address indexed identityAddress);
event SubscriptionForceClosed(address indexed identityAddress);
event PendingChangeCancelled(address indexed identityAddress);
event PendingChangeApplied(address indexed identityAddress, uint256 newPlanId);
event TrafficLimitExceeded(address indexed identityAddress);
event ServiceSuspended(address indexed identityAddress);
event ServiceResumed(address indexed identityAddress);
event TrafficReset(address indexed identityAddress, bool isDaily);
```

---

## 第四阶段：服务端配套修改

### 4.1 更新 ABI

**文件**: `subscription-service/abis/VPNSubscriptionV2.json`

重新生成 ABI:
```bash
cd contracts
forge build
cp out/VPNSubscriptionV2.sol/VPNSubscriptionV2.json ../subscription-service/abis/
```

### 4.2 修改服务端状态判断

**文件**: `subscription-service/index.js`

统一状态判断逻辑:

```javascript
function getSubscriptionStatus(subscription) {
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = Number(subscription.expiresAt);
    const autoRenewEnabled = Boolean(subscription.autoRenewEnabled);
    
    if (expiresAt <= now) {
        return 'expired';
    }
    
    if (autoRenewEnabled) {
        return 'active';  // 当前有效且会续费
    } else {
        return 'cancelled';  // 当前有效但已取消续费
    }
}
```

### 4.3 删除对废弃字段的读取

删除所有对以下字段的读取:
- `nextRenewalAt`
- `nextPlanId`
- `trafficUsedDaily`
- `trafficUsedMonthly`
- `lastResetDaily`
- `lastResetMonthly`
- `isSuspended`

### 4.4 删除对废弃函数的调用

删除所有对以下函数的调用:
- `getAllActiveSubscriptions()`
- `finalizeExpired()`
- 流量相关函数

### 4.5 修改自动续费服务

**文件**: `subscription-service/auto-renew.js`

简化续费逻辑:

```javascript
async function scanExpiringSoon() {
    // 从事件日志或本地数据库获取订阅列表
    const allIdentities = await loadIdentitiesFromEvents();
    
    const expiringSoon = [];
    const now = Math.floor(Date.now() / 1000);
    const window = 3600; // 1小时内到期
    
    for (const identity of allIdentities) {
        const sub = await contract.getSubscription(identity);
        const expiresAt = Number(sub.expiresAt);
        const autoRenewEnabled = Boolean(sub.autoRenewEnabled);
        
        // 只看 expiresAt 和 autoRenewEnabled
        if (autoRenewEnabled && 
            expiresAt > now && 
            expiresAt <= now + window) {
            expiringSoon.push(identity);
        }
    }
    
    return expiringSoon;
}
```

---

## 第五阶段：测试

### 5.1 单元测试

**文件**: `contracts/test/VPNSubscriptionV2.t.sol`

重点测试:
1. 首次订阅
2. 取消后当前周期仍可用
3. 到期后不再续费
4. 续费成功延长到期时间
5. 续费失败不修改到期时间
6. 过期后再次订阅（覆盖旧记录）
7. 立即升级套餐
8. 升级后 `autoRenewEnabled` 不变

### 5.2 集成测试

测试场景:
1. 完整订阅生命周期（订阅 → 续费 → 取消 → 过期 → 重订）
2. 升级套餐后续费
3. 取消后升级套餐
4. 多个订阅并发续费

---

## 第六阶段：部署和迁移

### 6.1 部署新合约

```bash
cd contracts
forge script script/DeployVPNSubscriptionV2.s.sol --rpc-url $RPC_URL --broadcast
```

### 6.2 迁移现有订阅（如果需要）

如果有现有订阅需要迁移:
1. 读取旧合约所有订阅
2. 过滤出未过期的订阅
3. 在新合约中重建订阅记录（使用管理员函数）

### 6.3 更新服务端配置

```javascript
// subscription-service/config.js
module.exports = {
    contractAddress: '0x新合约地址',
    // ...
};
```

### 6.4 重启服务

```bash
cd subscription-service
pm2 restart subscription-service
```

---

## 实施时间表

| 阶段 | 任务 | 预计时间 |
|------|------|----------|
| 1 | 精简 Subscription 结构体 | 1 小时 |
| 2 | 修改核心函数 | 3 小时 |
| 3 | 修改事件 | 30 分钟 |
| 4 | 服务端配套修改 | 2 小时 |
| 5 | 测试 | 3 小时 |
| 6 | 部署和迁移 | 1 小时 |
| **总计** | | **10.5 小时** |

---

## 风险和注意事项

### 风险 1: 现有订阅数据丢失
**缓解措施**: 部署前备份旧合约数据，提供迁移脚本

### 风险 2: 服务端和合约不同步
**缓解措施**: 先部署合约，再更新服务端，使用灰度发布

### 风险 3: 用户体验中断
**缓解措施**: 在低峰期部署，提前通知用户

---

## 验收标准

1. ✅ 合约编译通过，无警告
2. ✅ 所有单元测试通过
3. ✅ 集成测试通过
4. ✅ 服务端状态判断正确
5. ✅ 自动续费服务正常运行
6. ✅ 前端订阅状态显示正确
7. ✅ Gas 消耗降低（相比旧合约）
8. ✅ 代码行数减少 30% 以上

---

## 后续优化

重构完成后，可以考虑:
1. 添加批量续费功能（降低 gas）
2. 支持多种支付代币
3. 添加推荐奖励机制
4. 优化事件索引（降低服务端扫描成本）
