# 服务端重构计划

## 背景

合约重构阶段 1-4 已完成，合约结构发生了重大变化：

### 合约变更总结

**Subscription 结构体变化：**
- 从 16 个字段精简到 9 个字段
- 删除的字段：
  - `nextRenewalAt` - 下次续费时间（派生字段）
  - `nextPlanId` - 待生效套餐 ID
  - `trafficUsedDaily` - 今日已用流量
  - `trafficUsedMonthly` - 本月已用流量
  - `lastResetDaily` - 上次日流量重置时间
  - `lastResetMonthly` - 上次月流量重置时间
  - `isSuspended` - 暂停标志

**保留的字段（9 个）：**
```solidity
struct Subscription {
    address identityAddress;   // VPN 身份地址
    address payerAddress;      // 付款钱包地址
    uint96  lockedPrice;       // 锁定价格
    uint256 planId;            // 套餐 ID
    uint256 lockedPeriod;      // 锁定周期
    uint256 startTime;         // 开始时间
    uint256 expiresAt;         // 到期时间
    uint256 renewedAt;         // 最近一次续费时间
    bool    autoRenewEnabled;  // 自动续费开关
}
```

**删除的函数：**
- `finalizeExpired()` - 清理过期订阅
- `getAllActiveSubscriptions()` - 获取所有活跃订阅
- `getActiveSubscriptionCount()` - 获取活跃订阅数量
- `downgradeSubscription()` - 降级订阅
- `cancelPendingChange()` - 取消待生效变更
- 所有流量相关函数（reportTrafficUsage, checkTrafficLimit, suspendForTrafficLimit 等）

**核心设计原则：**
- 合约只保存关键事实，不保存派生状态
- 订阅状态通过 `expiresAt` 和 `autoRenewEnabled` 推导
- 不依赖 `finalizeExpired()` 保证正确性
- 过期后可直接覆盖重新订阅
- 复杂运营逻辑全部下放到服务端

---

## 服务端重构目标

1. **删除对已删除字段的所有引用**
2. **删除对已删除函数的所有调用**
3. **统一订阅状态判断逻辑**
4. **简化续费服务逻辑**
5. **将流量追踪完全移到服务端**

---

## 影响的文件清单

根据代码搜索结果，以下文件需要修改：

### 1. `index.js` - 主服务文件
**影响范围：** 多处引用已删除字段
**修改优先级：** 🔴 高

**需要修改的地方：**
- 第 363 行：`isSuspended` 字段读取
- 第 369 行：`isSuspended` 字段使用
- 第 373 行：`isActive` 计算逻辑（包含 `isSuspended`）
- 第 430 行：`isSuspended` 字段使用
- 第 547 行：`isSuspended` 字段使用
- 第 658 行：`isSuspended` 字段读取
- 第 871-878 行：`isSuspended` 字段使用
- 第 1175 行：`isSuspended` 字段初始化
- 第 1181-1182 行：`trafficUsedDaily`, `trafficUsedMonthly` 字段读取
- 第 1185 行：`isSuspended` 字段读取
- 第 1194 行：`isSuspended` 字段使用
- 第 1302-1309 行：所有已删除字段的读取和返回
- 第 1351-1358 行：所有已删除字段的读取和返回

### 2. `renewal-service.js` - 续费服务
**影响范围：** 多处引用已删除字段
**修改优先级：** 🔴 高

**需要修改的地方：**
- 第 114 行：`nextRenewalAt` 字段读取
- 第 116 行：`isSuspended` 字段读取
- 第 118 行：`timeUntilNextRenewal` 计算（基于 `nextRenewalAt`）
- 第 120 行：日志输出包含 `isSuspended`
- 第 122 行：日志输出包含 `nextRenewalAt`
- 第 124 行：`isSuspended` 检查逻辑
- 第 188 行：`nextPlanId` 字段读取
- 第 192 行：`nextRenewalAt` 字段读取
- 第 195 行：日志输出包含 `nextPlanId` 和 `isSuspended`
- 第 196 行：日志输出包含 `nextRenewalAt`
- 第 198-199 行：`nextPlanId` 检查和日志
- 第 230 行：日志输出包含 `nextRenewalAt`
- 第 232-233 行：`nextPlanId` 检查和日志

### 3. `traffic-tracker.js` - 流量追踪
**影响范围：** 整个文件依赖已删除的流量字段
**修改优先级：** 🟡 中（可选功能）

**需要修改的地方：**
- 第 23 行：ABI 定义包含已删除字段
- 第 146 行：`isSuspended` 字段读取
- 第 149 行：`isSuspended` 检查逻辑
- 第 258-259 行：`lastResetDaily`, `lastResetMonthly` 字段读取
- 第 262 行：基于 `lastResetDaily` 的计算
- 第 270 行：基于 `lastResetMonthly` 的计算

**建议：** 将流量追踪完全移到服务端数据库，不再依赖合约

### 4. `mock-db.js` - 模拟数据库
**影响范围：** 数据结构定义
**修改优先级：** 🟢 低

**需要修改的地方：**
- 第 19 行：`pendingChanges` 数据结构（包含 `nextPlanId`）

### 5. `cleanup-expired.js` - 清理过期订阅
**影响范围：** 调用已删除的函数
**修改优先级：** 🔴 高

**需要修改的地方：**
- 可能调用 `finalizeExpired()` 函数（需要完全删除或重写）

---

## 详细修改方案

### 阶段 1：统一订阅状态判断逻辑

**目标：** 创建统一的状态判断函数，替换所有分散的状态判断逻辑

**新增函数：** `getSubscriptionStatus(subscription)`

```javascript
/**
 * 统一的订阅状态判断函数
 * @param {Object} subscription - 订阅对象
 * @returns {Object} 状态信息
 */
function getSubscriptionStatus(subscription) {
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = Number(subscription.expiresAt);
    const autoRenewEnabled = Boolean(subscription.autoRenewEnabled);
    
    // 核心判断逻辑：只看 expiresAt 和 autoRenewEnabled
    const isExpired = expiresAt <= now;
    const isActive = expiresAt > now;
    
    let status;
    if (isExpired) {
        status = 'expired';
    } else if (autoRenewEnabled) {
        status = 'active';  // 当前有效且会续费
    } else {
        status = 'cancelled';  // 当前有效但已取消续费
    }
    
    return {
        status,           // 'active' | 'cancelled' | 'expired'
        isActive,         // 当前是否有效
        isExpired,        // 是否已过期
        autoRenewEnabled, // 是否会自动续费
        expiresAt,        // 到期时间
    };
}
```

**修改位置：**
- `index.js` - 所有状态判断的地方
- `renewal-service.js` - 续费前的状态检查

---

### 阶段 2：修改 `index.js`

#### 2.1 删除 `isSuspended` 相关代码

**第 363-373 行：** 删除 `isSuspended` 字段读取和使用

```javascript
// 修改前：
const isSuspended = Boolean(subscription.isSuspended ?? subscription[13]);
// ...
return {
  // ...
  isSuspended,
  // ...
  isActive: expiresAt > now && !isSuspended,
};

// 修改后：
const { status, isActive } = getSubscriptionStatus(subscription);
return {
  // ...
  status,
  isActive,
  // 删除 isSuspended 字段
};
```

#### 2.2 删除流量字段读取

**第 1181-1194 行：** 删除流量字段读取

```javascript
// 修改前：
const dailyUsed = Number(sub.trafficUsedDaily ?? sub[9] ?? 0);
const monthlyUsed = Number(sub.trafficUsedMonthly ?? sub[10] ?? 0);
// ...
const isSuspended = Boolean(sub.isSuspended ?? sub[13]);

// 修改后：
// 完全删除这些行，流量追踪移到服务端数据库
```

#### 2.3 修改订阅详情返回

**第 1302-1309 行和 1351-1358 行：** 删除已删除字段的返回

```javascript
// 修改前：
return {
  // ...
  nextRenewalAt: sub[8].toString(),
  autoRenewEnabled: Boolean(sub[9]),
  nextPlanId: Number(sub[10]),
  trafficUsedDaily: sub[11].toString(),
  trafficUsedMonthly: sub[12].toString(),
  lastResetDaily: sub[13].toString(),
  lastResetMonthly: sub[14].toString(),
  isSuspended: Boolean(sub[15]),
};

// 修改后：
const { status, isActive } = getSubscriptionStatus(sub);
return {
  identityAddress: sub[0],
  payerAddress: sub[1],
  lockedPrice: sub[2].toString(),
  planId: Number(sub[3]),
  lockedPeriod: Number(sub[4]),
  startTime: Number(sub[5]),
  expiresAt: Number(sub[6]),
  renewedAt: Number(sub[7]),
  autoRenewEnabled: Boolean(sub[8]),
  status,      // 新增：派生状态
  isActive,    // 新增：是否有效
};
```

---

### 阶段 3：修改 `renewal-service.js`

#### 3.1 简化续费前检查逻辑

**第 114-124 行：** 删除 `nextRenewalAt` 和 `isSuspended` 检查

```javascript
// 修改前：
const nextRenewalAt = Number(subscription[8]);
// ...
const isSuspended = Boolean(subscription[15]);
const timeUntilNextRenewal = nextRenewalAt - now;
// ...
if (isSuspended) {
  console.log(`  [${identityAddress}] ⏸️  订阅已暂停，跳过续费`);
  continue;
}

// 修改后：
const { status, isActive, isExpired } = getSubscriptionStatus(subscription);

// 只检查是否过期和是否启用自动续费
if (!isExpired) {
  console.log(`  [${identityAddress}] ⏰ 订阅尚未到期，跳过续费`);
  continue;
}

if (!autoRenewEnabled) {
  console.log(`  [${identityAddress}] 🚫 自动续费已关闭，跳过续费`);
  continue;
}
```

#### 3.2 删除 `nextPlanId` 相关逻辑

**第 188-199 行和 232-233 行：** 删除待生效套餐变更逻辑

```javascript
// 修改前：
const nextPlanId = Number(fullSubscription.nextPlanId);
// ...
if (nextPlanId > 0) {
  console.log(`  [${identityAddress}] 📋 检测到待生效的套餐变更: planId ${subscription[3]} -> ${nextPlanId}`);
}

// 修改后：
// 完全删除这些行，不再支持链上的待生效套餐变更
```

#### 3.3 简化续费时机判断

**第 192-196 行：** 使用 `expiresAt` 替代 `nextRenewalAt`

```javascript
// 修改前：
const nextRenewalAt = Number(fullSubscription.nextRenewalAt);
console.log(`  [${identityAddress}] 续费前时间: now=${formatTimestamp(now)}, renewedAt=${formatTimestamp(renewedAt)}, expiresAt=${formatTimestamp(expiresAt)}, nextRenewalAt=${formatTimestamp(nextRenewalAt)}, lockedPeriod=${lockedPeriod}s`);

// 修改后：
console.log(`  [${identityAddress}] 续费前时间: now=${formatTimestamp(now)}, renewedAt=${formatTimestamp(renewedAt)}, expiresAt=${formatTimestamp(expiresAt)}, lockedPeriod=${lockedPeriod}s`);

// 续费时机判断：基于 expiresAt
if (now < expiresAt) {
  console.log(`  [${identityAddress}] ⏰ 尚未到期，跳过续费`);
  continue;
}

if (now > expiresAt + RENEWAL_GRACE_PERIOD) {
  console.log(`  [${identityAddress}] ⏰ 超过续费宽限期，跳过续费`);
  continue;
}
```

---

### 阶段 4：处理 `traffic-tracker.js`

**建议方案：** 将流量追踪完全移到服务端

#### 4.1 创建服务端流量数据库表

```javascript
// 新增数据结构
const trafficUsage = {
  // identityAddress -> { dailyUsed, monthlyUsed, lastResetDaily, lastResetMonthly }
};
```

#### 4.2 修改流量追踪逻辑

```javascript
// 不再从合约读取流量数据
// 改为从服务端数据库读取和更新

function trackTraffic(identityAddress, bytesUsed) {
  const now = Math.floor(Date.now() / 1000);
  
  if (!trafficUsage[identityAddress]) {
    trafficUsage[identityAddress] = {
      dailyUsed: 0,
      monthlyUsed: 0,
      lastResetDaily: now,
      lastResetMonthly: now,
    };
  }
  
  const usage = trafficUsage[identityAddress];
  
  // 检查是否需要重置
  const daysSinceReset = Math.floor((now - usage.lastResetDaily) / 86400);
  if (daysSinceReset >= 1) {
    usage.dailyUsed = 0;
    usage.lastResetDaily = now;
  }
  
  const currentMonth = new Date(now * 1000).getUTCMonth();
  const lastResetMonth = new Date(usage.lastResetMonthly * 1000).getUTCMonth();
  if (currentMonth !== lastResetMonth) {
    usage.monthlyUsed = 0;
    usage.lastResetMonthly = now;
  }
  
  // 更新流量
  usage.dailyUsed += bytesUsed;
  usage.monthlyUsed += bytesUsed;
  
  return usage;
}
```

#### 4.3 删除合约流量函数调用

```javascript
// 删除所有对以下函数的调用：
// - reportTrafficUsage()
// - checkTrafficLimit()
// - suspendForTrafficLimit()
// - resumeAfterReset()
// - resetDailyTraffic()
// - resetMonthlyTraffic()
```

---

### 阶段 5：修改 `cleanup-expired.js`

**目标：** 删除或重写清理过期订阅的逻辑

#### 5.1 删除 `finalizeExpired()` 调用

```javascript
// 修改前：
await contract.finalizeExpired(identityAddress, forceClose);

// 修改后：
// 完全删除这个调用
// 过期订阅不需要清理，可以直接被新订阅覆盖
```

#### 5.2 可选：保留清理逻辑用于服务端数据

```javascript
// 如果需要清理服务端数据库中的过期记录
function cleanupExpiredSubscriptions() {
  const now = Math.floor(Date.now() / 1000);
  const CLEANUP_THRESHOLD = 30 * 86400; // 30 天
  
  // 从服务端数据库中删除过期超过 30 天的记录
  // 这不影响链上数据
}
```

---

### 阶段 6：修改 `mock-db.js`

**第 19 行：** 删除 `pendingChanges` 数据结构

```javascript
// 修改前：
pendingChanges: {}  // identityAddress -> { nextPlanId, intentSignature }

// 修改后：
// 完全删除这个字段，不再支持链上的待生效套餐变更
```

---

## 实施顺序

### 第一步：创建统一状态判断函数
- 在 `index.js` 中添加 `getSubscriptionStatus()` 函数
- 编写单元测试验证逻辑正确性

### 第二步：修改 `index.js`
- 替换所有状态判断逻辑
- 删除已删除字段的读取和返回
- 测试 API 端点

### 第三步：修改 `renewal-service.js`
- 简化续费前检查逻辑
- 删除 `nextPlanId` 相关逻辑
- 使用 `expiresAt` 替代 `nextRenewalAt`
- 测试续费流程

### 第四步：处理 `traffic-tracker.js`
- 创建服务端流量数据库
- 修改流量追踪逻辑
- 删除合约流量函数调用
- 测试流量追踪功能

### 第五步：修改 `cleanup-expired.js`
- 删除 `finalizeExpired()` 调用
- 可选：保留服务端数据清理逻辑
- 测试清理流程

### 第六步：修改 `mock-db.js`
- 删除 `pendingChanges` 数据结构
- 更新相关测试

---

## 测试计划

### 单元测试
1. 测试 `getSubscriptionStatus()` 函数的所有分支
2. 测试订阅状态判断逻辑
3. 测试续费时机判断逻辑

### 集成测试
1. 完整订阅生命周期测试
   - 订阅 → 续费 → 取消 → 过期 → 重订
2. 升级套餐后续费测试
3. 取消后升级套餐测试
4. 多个订阅并发续费测试

### 回归测试
1. 验证所有 API 端点正常工作
2. 验证前端集成正常
3. 验证续费服务正常运行

---

## 风险和注意事项

### 风险 1：服务端和合约不同步
**缓解措施：** 
- 先部署合约，再更新服务端
- 使用灰度发布
- 保留旧版本服务端作为回滚备份

### 风险 2：流量追踪数据丢失
**缓解措施：**
- 在切换前导出现有流量数据
- 提供数据迁移脚本
- 保留旧合约的流量数据作为历史记录

### 风险 3：用户体验中断
**缓解措施：**
- 在低峰期部署
- 提前通知用户
- 准备回滚方案

---

## 验收标准

1. ✅ 所有对已删除字段的引用已删除
2. ✅ 所有对已删除函数的调用已删除
3. ✅ 订阅状态判断逻辑统一且正确
4. ✅ 续费服务正常运行
5. ✅ 流量追踪功能正常（如果保留）
6. ✅ 所有单元测试通过
7. ✅ 所有集成测试通过
8. ✅ 前端集成正常
9. ✅ 无回归问题

---

## 后续优化

重构完成后，可以考虑：
1. 添加批量续费功能（降低 gas）
2. 优化事件索引（降低服务端扫描成本）
3. 添加订阅状态缓存（提高查询性能）
4. 实现更完善的流量追踪和限制功能
