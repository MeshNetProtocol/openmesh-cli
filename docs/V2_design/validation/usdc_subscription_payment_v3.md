# VPN 订阅支付技术方案 V2.1 — 订阅分级系统 + 流量管理

**创建日期**: 2026-04-13  
**最后更新**: 2026-04-14  
**基于**: V3.3 技术验证实现  
**当前状态**: Phase 1-2 已完成,Phase 3-5 待实施

---

## 一、方案概述

本方案是基于 V3.3 (CDP Paymaster + Permit + Server Wallet) 的增强版本,在保留原有 0 gas 订阅能力的基础上,新增了:

1. **订阅分级系统**: Free/Basic/Premium 三层套餐
2. **流量管理**: 日/月流量限制、自动暂停、定期重置
3. **订阅变更**: 立即升级(Proration 补差价)、下周期降级、取消变更
4. **灵活计费**: 月付/年付双模式

### 核心架构

```
用户 (MetaMask, 0 gas)
  ↓ EIP-712 签名
后端服务 (Node.js)
  ↓ CDP Smart Account
CDP Paymaster (赞助 gas)
  ↓
Base Sepolia/Mainnet
  ├─ VPNSubscriptionV2 合约
  └─ USDC 合约
```

---

## 二、订阅分级系统

### 2.1 套餐设计

| 套餐 | planId | 月价 | 年价 | 日流量限制 | 月流量限制 | 等级 |
|------|--------|------|------|-----------|-----------|------|
| Free | 2 | 0 USDC | 0 USDC | 100 MB | 无限 | 0 |
| Basic | 3 | 5 USDC | 50 USDC | 无限 | 100 GB | 1 |
| Premium | 4 | 10 USDC | 100 USDC | 无限 | 无限 | 2 |

**说明**:
- planId 1 已废弃(V1 遗留)
- Free 套餐适合轻度用户,每日限额防止滥用
- Basic 套餐适合中度用户,月度流量包
- Premium 套餐无限流量,适合重度用户

### 2.2 套餐数据结构

```solidity
struct Plan {
    string  name;                  // 套餐名称
    uint256 pricePerMonth;         // 月价格 (USDC, 6 decimals)
    uint256 pricePerYear;          // 年价格 (USDC, 6 decimals)
    uint256 period;                // 默认周期 (兼容)
    uint256 trafficLimitDaily;     // 每日流量限制 (bytes, 0 = 无限)
    uint256 trafficLimitMonthly;   // 每月流量限制 (bytes, 0 = 无限)
    uint8   tier;                  // 套餐等级 (0=Free, 1=Basic, 2=Premium)
    bool    isActive;              // 是否可用
}
```

---

## 三、订阅数据结构

### 3.1 Subscription 结构

```solidity
struct Subscription {
    address identityAddress;       // VPN 身份地址
    address payerAddress;          // 付款钱包地址
    uint96  lockedPrice;           // 锁定价格
    uint256 planId;                // 当前套餐 ID
    uint256 lockedPeriod;          // 锁定周期
    uint256 startTime;             // 开始时间
    uint256 expiresAt;             // 到期时间
    bool    autoRenewEnabled;      // 自动续费开关
    bool    isActive;              // 是否活跃
    
    // V2.1 新增字段
    uint256 nextPlanId;            // 下周期套餐 ID (0 = 无变更)
    uint256 trafficUsedDaily;      // 今日已用流量 (bytes)
    uint256 trafficUsedMonthly;    // 本月已用流量 (bytes)
    uint256 lastResetDaily;        // 上次日流量重置时间
    uint256 lastResetMonthly;      // 上次月流量重置时间
}
```

**关键变化**:
- `nextPlanId`: 支持降级预约(下周期生效)
- 流量追踪字段: 实现流量限制和自动暂停

---

## 四、核心功能

### 4.1 首次订阅 (保持 V3.3 流程)

```
① 用户选择套餐 (Free/Basic/Premium) + 计费周期 (月付/年付)
② 前端请求两个签名:
   - SubscribeIntent (EIP-712): 包含 planId, isYearly, maxAmount
   - ERC-2612 permit: USDC 授权
③ 后端调用 permitAndSubscribe()
④ 合约验证签名 → permit → 扣款 → 创建订阅
⑤ 后端监听 SubscriptionCreated 事件 → 激活 VPN
```

**EIP-712 签名类型**:
```solidity
SubscribeIntent(
    address user,
    address identityAddress,
    uint256 planId,
    bool isYearly,
    uint256 maxAmount,
    uint256 deadline,
    uint256 nonce
)
```

### 4.2 流量管理

#### 4.2.1 流量上报

```
VPN 服务器 → POST /api/traffic/record
  { identityAddress, bytesUsed }
  ↓
后端缓存 (trafficBuffer)
  ↓ 每 5 分钟批量上报
合约 reportTrafficUsage(identityAddress, bytesUsed)
  ↓
更新 trafficUsedDaily / trafficUsedMonthly
```

#### 4.2.2 流量限制检查

```solidity
function checkTrafficLimit(address identityAddress) 
    external view returns (
        bool withinLimit,
        uint256 dailyUsed,
        uint256 dailyLimit,
        uint256 monthlyUsed,
        uint256 monthlyLimit
    )
```

**超限处理**:
```
后端检测超限 → suspendForTrafficLimit(identityAddress)
  ↓
合约标记 isActive = false
  ↓
后端从 Xray 删除用户 (停服)
```

#### 4.2.3 流量重置

```
后端定时任务 (每小时检查):
  - 日流量重置: 每天 UTC 00:00
  - 月流量重置: 每月 1 号 UTC 00:00
  ↓
resetDailyTraffic() / resetMonthlyTraffic()
  ↓
trafficUsed* = 0, lastReset* = now
  ↓
resumeAfterReset() (如果之前被暂停)
```

### 4.3 订阅升级 (立即生效 + Proration)

```
① 用户选择更高等级套餐
② 前端查询补差价: GET /api/subscription/proration
   ?identityAddress=0x...&newPlanId=4
③ 前端签名 UpgradeIntent (EIP-712)
④ 后端调用 upgradeSubscription()
⑤ 合约计算补差价:
   prorationAmount = (newPrice - oldPrice) * remainingDays / totalDays
⑥ 扣款 → 立即切换套餐 → 更新 expiresAt
```

**Proration 算法**:
```solidity
function calculateUpgradeProration(
    address identityAddress,
    uint256 newPlanId
) external view returns (uint256 prorationAmount) {
    Subscription memory sub = subscriptions[identityAddress];
    Plan memory newPlan = plans[newPlanId];
    
    uint256 remainingTime = sub.expiresAt - block.timestamp;
    uint256 newPrice = sub.lockedPeriod == 365 days 
        ? newPlan.pricePerYear 
        : newPlan.pricePerMonth;
    uint256 oldPrice = sub.lockedPrice;
    
    // 按时间比例计算补差价
    prorationAmount = (newPrice - oldPrice) * remainingTime / sub.lockedPeriod;
}
```

**EIP-712 签名类型**:
```solidity
UpgradeIntent(
    address user,
    address identityAddress,
    uint256 newPlanId,
    bool isYearly,
    uint256 maxAmount,
    uint256 deadline,
    uint256 nonce
)
```

### 4.4 订阅降级 (下周期生效)

```
① 用户选择更低等级套餐
② 前端签名 DowngradeIntent (EIP-712)
③ 后端调用 downgradeSubscription()
④ 合约设置 nextPlanId = newPlanId
⑤ 当前周期继续使用旧套餐
⑥ 续费时自动应用变更:
   executeRenewal() → _applyPendingChange() → planId = nextPlanId
```

**EIP-712 签名类型**:
```solidity
DowngradeIntent(
    address user,
    address identityAddress,
    uint256 newPlanId,
    uint256 nonce
)
```

### 4.5 取消待生效变更

```
① 用户取消降级预约
② 前端签名 CancelChangeIntent (EIP-712)
③ 后端调用 cancelPendingChange()
④ 合约设置 nextPlanId = 0
```

**EIP-712 签名类型**:
```solidity
CancelChangeIntent(
    address user,
    address identityAddress,
    uint256 nonce
)
```

### 4.6 自动续费 (支持套餐变更)

```
后端定时任务:
  ① 检查 expiresAt <= now 的订阅
  ② 检查 nextPlanId:
     - nextPlanId > 0: 应用套餐变更
     - nextPlanId = 0: 使用当前套餐
  ③ 调用 executeRenewal(identityAddress)
  ④ 合约扣款 → 更新 expiresAt → 应用 nextPlanId
```

**合约逻辑**:
```solidity
function executeRenewal(address identityAddress) external {
    // ... 扣款逻辑 ...
    
    // 应用待生效的套餐变更
    if (sub.nextPlanId > 0) {
        _applyPendingChange(identityAddress);
    }
    
    sub.expiresAt += sub.lockedPeriod;
}

function _applyPendingChange(address identityAddress) internal {
    Subscription storage sub = subscriptions[identityAddress];
    Plan memory newPlan = plans[sub.nextPlanId];
    
    sub.planId = sub.nextPlanId;
    sub.lockedPrice = uint96(newPlan.pricePerMonth); // 或 pricePerYear
    sub.nextPlanId = 0;
    
    emit PendingChangeApplied(identityAddress, sub.planId);
}
```

---

## 五、后端 API

### 5.1 套餐管理

```
GET /api/plans
返回: { plans: [{ planId, name, pricePerMonth, pricePerYear, ... }] }

GET /api/plan/:planId
返回: { plan: { ... } }
```

### 5.2 流量管理

```
GET /api/traffic/:identityAddress
返回: {
  traffic: {
    withinLimit: true,
    daily: { used: "50.00 MB", limit: "100.00 MB", ... },
    monthly: { used: "5.00 GB", limit: "100.00 GB", ... }
  }
}

POST /api/traffic/record
请求: { identityAddress, bytesUsed }
返回: { success: true }
```

### 5.3 订阅变更

```
GET /api/subscription/proration
参数: identityAddress, newPlanId
返回: { prorationAmount: "2500000" }

POST /api/subscription/upgrade
请求: { userAddress, identityAddress, newPlanId, isYearly, maxAmount, deadline, intentNonce, intentSig, permitSig }
返回: { success: true, txHash }

POST /api/subscription/downgrade
请求: { userAddress, identityAddress, newPlanId, nonce, sig }
返回: { success: true, txHash }

POST /api/subscription/cancel-change
请求: { userAddress, identityAddress, nonce, sig }
返回: { success: true, txHash }
```

---

## 六、前端集成

### 6.1 套餐选择界面

```typescript
// 查询所有套餐
const plans = await fetch('/api/plans').then(r => r.json());

// 显示套餐卡片
plans.forEach(plan => {
  // Free: 0 USDC/月, 100 MB/日
  // Basic: 5 USDC/月 或 50 USDC/年, 100 GB/月
  // Premium: 10 USDC/月 或 100 USDC/年, 无限流量
});
```

### 6.2 流量显示

```typescript
// 查询流量使用
const traffic = await fetch(`/api/traffic/${identityAddress}`).then(r => r.json());

// 显示进度条
<ProgressBar 
  value={traffic.daily.usedBytes} 
  max={traffic.daily.limitBytes}
  label={`${traffic.daily.used} / ${traffic.daily.limit}`}
/>

// 超限警告
if (!traffic.withinLimit) {
  showAlert('流量已超限,服务已暂停');
}
```

### 6.3 订阅升级

```typescript
// 1. 查询补差价
const { prorationAmount } = await fetch(
  `/api/subscription/proration?identityAddress=${addr}&newPlanId=4`
).then(r => r.json());

// 2. 签名 UpgradeIntent
const intentSig = await walletClient.signTypedData({
  domain: DOMAIN,
  types: UPGRADE_INTENT_TYPES,
  primaryType: 'UpgradeIntent',
  message: { user, identityAddress, newPlanId, isYearly, maxAmount, deadline, nonce }
});

// 3. 签名 permit
const permitSig = await walletClient.signTypedData({ /* ... */ });

// 4. 提交升级
await fetch('/api/subscription/upgrade', {
  method: 'POST',
  body: JSON.stringify({ /* ... */ })
});
```

### 6.4 订阅降级

```typescript
// 1. 签名 DowngradeIntent
const sig = await walletClient.signTypedData({
  domain: DOMAIN,
  types: DOWNGRADE_INTENT_TYPES,
  primaryType: 'DowngradeIntent',
  message: { user, identityAddress, newPlanId, nonce }
});

// 2. 提交降级
await fetch('/api/subscription/downgrade', {
  method: 'POST',
  body: JSON.stringify({ userAddress, identityAddress, newPlanId, nonce, sig })
});

// 3. 显示提示
showMessage('降级将在下个计费周期生效');
```

---

## 七、合约部署信息

### 7.1 Base Sepolia (测试网)

```
合约地址: 0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf
USDC 地址: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
Relayer: 0x8b8BB4F49a5E8f7F5c5e5e5e5e5e5e5e5e5e5e5e (CDP Server Wallet)
部署时间: 2026-04-13
```

### 7.2 初始套餐配置

```solidity
constructor() {
    plans[2] = Plan({
        name: "Free",
        pricePerMonth: 0,
        pricePerYear: 0,
        period: 30 days,
        trafficLimitDaily: 100 * 1024 * 1024,  // 100 MB
        trafficLimitMonthly: 0,                 // 无限
        tier: 0,
        isActive: true
    });
    
    plans[3] = Plan({
        name: "Basic",
        pricePerMonth: 5 * USDC_UNIT,
        pricePerYear: 50 * USDC_UNIT,
        period: 30 days,
        trafficLimitDaily: 0,                   // 无限
        trafficLimitMonthly: 100 * 1024 * 1024 * 1024, // 100 GB
        tier: 1,
        isActive: true
    });
    
    plans[4] = Plan({
        name: "Premium",
        pricePerMonth: 10 * USDC_UNIT,
        pricePerYear: 100 * USDC_UNIT,
        period: 30 days,
        trafficLimitDaily: 0,                   // 无限
        trafficLimitMonthly: 0,                 // 无限
        tier: 2,
        isActive: true
    });
}
```

---

## 八、实施进度

### Phase 1: 合约升级 ✅ 已完成

- ✅ 设计 Plan 结构 (流量限制字段)
- ✅ 更新 Subscription 结构 (nextPlanId, 流量追踪)
- ✅ 实现套餐管理函数 (setPlan, disablePlan, getPlan)
- ✅ 实现流量管理函数 (reportTrafficUsage, checkTrafficLimit, suspend/resume, reset)
- ✅ 实现 Proration 算法 (calculateUpgradeProration)
- ✅ 实现订阅变更函数 (upgrade, downgrade, cancelChange, applyChange)
- ✅ 添加 EIP-712 签名类型 (UpgradeIntent, DowngradeIntent, CancelChangeIntent)
- ✅ 单元测试 (31 个测试用例全部通过)
- ✅ 部署到 Base Sepolia

### Phase 2: 后端开发 ✅ 已完成

- ✅ 创建本地 JSON 数据库 (mock-db.js)
- ✅ 实现 TrafficTracker 服务 (流量追踪、上报、重置)
- ✅ 添加套餐管理 API (GET /api/plans, GET /api/plan/:planId)
- ✅ 添加流量查询 API (GET /api/traffic/:identityAddress, POST /api/traffic/record)
- ✅ 添加订阅变更 API (upgrade, downgrade, cancel-change, proration)
- ✅ 更新自动续费服务 (支持 nextPlanId)
- ✅ 集成服务启动 (RenewalService + TrafficTracker)

### Phase 3: 前端开发 ⏸️ 未开始

- ⏸️ 设计套餐卡片 UI
- ⏸️ 实现流量进度条
- ⏸️ 实现订阅变更界面
- ⏸️ 实现 EIP-712 签名流程
- ⏸️ UI/UX 优化

### Phase 4: 集成测试 ⏸️ 未开始

- ⏸️ 功能测试 (免费版/基础版/高级版)
- ⏸️ 升级/降级测试
- ⏸️ 流量限制测试
- ⏸️ 性能测试
- ⏸️ 安全测试

### Phase 5: 上线部署 ⏸️ 未开始

- ⏸️ 部署到 Base 主网
- ⏸️ 数据迁移
- ⏸️ 监控配置
- ⏸️ 文档更新

---

## 九、与 V3.3 的差异总结

| 功能 | V3.3 | V2.1 (当前实现) |
|------|------|----------------|
| 套餐类型 | 月付/年付 | Free/Basic/Premium 三层 |
| 流量管理 | ❌ 无 | ✅ 日/月限制 + 自动暂停 |
| 订阅升级 | ❌ 无 | ✅ 立即生效 + Proration |
| 订阅降级 | ❌ 无 | ✅ 下周期生效 |
| 取消变更 | ❌ 无 | ✅ 支持 |
| 合约版本 | V1 | V2.1 |
| 部署地址 | 未部署 | 0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf |

---

## 十、测试指南

详见 [TESTING_GUIDE.md](phase4/TESTING_GUIDE.md)

---

## 十一、相关文档

- [重构进度追踪](phase4/REFACTORING_PROGRESS.md)
- [测试指南](phase4/TESTING_GUIDE.md)
- [合约部署文档](phase4/contracts/DEPLOYMENT.md)
- [后端 README](phase4/subscription-service/README.md)
- [前端 README](phase4/frontend/README.md)

---

**文档作者**: Claude Code  
**最后更新**: 2026-04-14  
**状态**: Phase 1-2 已完成,可进入测试阶段
