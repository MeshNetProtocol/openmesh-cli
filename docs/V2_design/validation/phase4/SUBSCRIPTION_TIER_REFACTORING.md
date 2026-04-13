# 订阅分级系统重构方案

## 文档信息
- **创建时间**: 2026-04-13
- **版本**: V2.1
- **状态**: 设计阶段

---

## 1. 需求概述

### 1.1 当前问题
当前 V2 订阅系统支持一个钱包为多个 VPN 身份订阅服务,但所有订阅都是同一套餐类型,缺乏灵活性和差异化定价。

### 1.2 新需求
实现三级订阅体系,支持:
1. **免费版 (Free Tier)**: 每日 100MB 流量限制,超限暂停服务
2. **基础版 (Basic Tier)**: 每月 100GB 流量,5 USDC/月,支持按年付费
3. **高级版 (Premium Tier)**: 无限流量,10 USDC/月,支持按月/按年付费
4. **多订阅支持**: 允许同一身份多次订阅,但新订阅在下个周期生效
5. **按比例退款 (Proration)**: 升级/降级时,将剩余未到期资金转换为新套餐资金

---

## 2. 行业最佳实践分析

### 2.1 订阅分级模式
参考 SaaS 行业常见做法:
- **Freemium 模式**: 免费版吸引用户,付费版提供增值服务
- **Good-Better-Best**: 三级定价,覆盖不同用户群体
- **Usage-Based Pricing**: 基于流量使用量计费

### 2.2 Proration 算法
常见的按比例计费方法:
1. **时间比例法**: 按剩余天数/总天数计算退款
2. **使用量比例法**: 按已用流量/总流量计算
3. **混合法**: 结合时间和使用量

**推荐方案**: 时间比例法
- 公式: `退款金额 = 当前套餐价格 × (剩余天数 / 总天数)`
- 优点: 简单透明,用户易理解
- 缺点: 不考虑实际使用量

### 2.3 订阅变更策略
1. **立即生效 (Immediate)**: 升级立即生效,降级下周期生效
2. **下周期生效 (Next Cycle)**: 所有变更都在下周期生效
3. **混合策略**: 升级立即生效+Proration,降级下周期生效

**推荐方案**: 混合策略
- 升级: 立即生效,按比例补差价
- 降级: 下周期生效,避免退款复杂性
- 新订阅: 立即生效

---

## 3. 系统架构设计

### 3.1 订阅套餐定义

```solidity
struct Plan {
    uint256 id;                    // 套餐 ID
    string name;                   // 套餐名称
    uint256 pricePerMonth;         // 月价格 (USDC, 6 decimals)
    uint256 pricePerYear;          // 年价格 (USDC, 6 decimals)
    uint256 trafficLimitDaily;     // 每日流量限制 (bytes, 0 = 无限)
    uint256 trafficLimitMonthly;   // 每月流量限制 (bytes, 0 = 无限)
    uint8 tier;                    // 套餐等级 (0=Free, 1=Basic, 2=Premium)
    bool isActive;                 // 是否可用
}
```

**初始套餐配置**:
```javascript
Plan 1: {
    id: 1,
    name: "Free",
    pricePerMonth: 0,
    pricePerYear: 0,
    trafficLimitDaily: 100 * 1024 * 1024,      // 100 MB
    trafficLimitMonthly: 0,                     // 不限月流量
    tier: 0,
    isActive: true
}

Plan 2: {
    id: 2,
    name: "Basic",
    pricePerMonth: 5_000000,                    // 5 USDC
    pricePerYear: 50_000000,                    // 50 USDC (年付 8.3 折)
    trafficLimitDaily: 0,                       // 不限日流量
    trafficLimitMonthly: 100 * 1024 * 1024 * 1024, // 100 GB
    tier: 1,
    isActive: true
}

Plan 3: {
    id: 3,
    name: "Premium",
    pricePerMonth: 10_000000,                   // 10 USDC
    pricePerYear: 100_000000,                   // 100 USDC (年付 8.3 折)
    trafficLimitDaily: 0,                       // 无限
    trafficLimitMonthly: 0,                     // 无限
    tier: 2,
    isActive: true
}
```

### 3.2 订阅数据结构

```solidity
struct Subscription {
    address identityAddress;       // VPN 身份地址
    address payerAddress;          // 付款钱包地址
    uint256 planId;                // 当前套餐 ID
    uint256 lockedPrice;           // 锁定价格
    uint256 lockedPeriod;          // 锁定周期 (秒)
    uint256 startTime;             // 开始时间
    uint256 expiresAt;             // 到期时间
    bool autoRenewEnabled;         // 自动续费开关
    bool isActive;                 // 是否激活
    
    // 新增字段
    uint256 nextPlanId;            // 下周期套餐 ID (0 = 无变更)
    uint256 trafficUsedDaily;      // 今日已用流量 (bytes)
    uint256 trafficUsedMonthly;    // 本月已用流量 (bytes)
    uint256 lastResetDaily;        // 上次日流量重置时间
    uint256 lastResetMonthly;      // 上次月流量重置时间
}
```

### 3.3 流量追踪架构

**链下追踪 (推荐)**:
- VPN 服务器实时记录流量使用
- 定期同步到后端数据库
- 超限时调用合约暂停服务

**链上追踪 (备选)**:
- 每次 VPN 连接时上报流量
- Gas 成本高,不推荐

**混合方案**:
- 日常流量链下追踪
- 关键事件 (超限/重置) 链上记录

---

## 4. 合约功能设计

### 4.1 新增函数

#### 4.1.1 套餐管理
```solidity
// 添加/更新套餐
function setPlan(
    uint256 planId,
    string memory name,
    uint256 pricePerMonth,
    uint256 pricePerYear,
    uint256 trafficLimitDaily,
    uint256 trafficLimitMonthly,
    uint8 tier
) external onlyOwner;

// 禁用套餐
function disablePlan(uint256 planId) external onlyOwner;

// 查询套餐
function getPlan(uint256 planId) external view returns (Plan memory);
```

#### 4.1.2 订阅变更
```solidity
// 升级订阅 (立即生效 + Proration)
function upgradeSubscription(
    address identityAddress,
    uint256 newPlanId,
    bool isYearly,
    bytes calldata signature,
    bytes calldata permitSignature
) external;

// 降级订阅 (下周期生效)
function downgradeSubscription(
    address identityAddress,
    uint256 newPlanId,
    bytes calldata signature
) external;

// 取消下周期变更
function cancelPendingChange(
    address identityAddress,
    bytes calldata signature
) external;
```

#### 4.1.3 流量管理
```solidity
// 上报流量使用 (仅 Relayer)
function reportTrafficUsage(
    address identityAddress,
    uint256 bytesUsed
) external onlyRelayer;

// 检查流量限制
function checkTrafficLimit(
    address identityAddress
) external view returns (bool isWithinLimit, uint256 remaining);

// 暂停服务 (超限)
function suspendForTrafficLimit(
    address identityAddress
) external onlyRelayer;

// 恢复服务 (流量重置后)
function resumeAfterReset(
    address identityAddress
) external onlyRelayer;
```

### 4.2 Proration 算法实现

```solidity
/**
 * 计算升级补差价
 * @param identityAddress VPN 身份地址
 * @param newPlanId 新套餐 ID
 * @return additionalPayment 需要补缴的金额
 */
function calculateUpgradeProration(
    address identityAddress,
    uint256 newPlanId
) public view returns (uint256 additionalPayment) {
    Subscription storage sub = subscriptions[identityAddress];
    require(sub.isActive, "VPN: subscription not active");
    
    Plan storage currentPlan = plans[sub.planId];
    Plan storage newPlan = plans[newPlanId];
    
    require(newPlan.tier > currentPlan.tier, "VPN: not an upgrade");
    
    // 计算剩余天数
    uint256 remainingTime = sub.expiresAt - block.timestamp;
    uint256 totalPeriod = sub.lockedPeriod;
    
    // 当前套餐剩余价值
    uint256 currentValue = (sub.lockedPrice * remainingTime) / totalPeriod;
    
    // 新套餐剩余周期价值
    uint256 newValue = (newPlan.pricePerMonth * remainingTime) / 30 days;
    
    // 补差价
    if (newValue > currentValue) {
        additionalPayment = newValue - currentValue;
    } else {
        additionalPayment = 0; // 不退款
    }
}
```

---

## 5. 后端 API 设计

### 5.1 新增 API 端点

#### 5.1.1 套餐查询
```javascript
// GET /api/plans
// 返回所有可用套餐
{
    "plans": [
        {
            "id": 1,
            "name": "Free",
            "pricePerMonth": "0",
            "pricePerYear": "0",
            "trafficLimitDaily": "104857600",
            "trafficLimitMonthly": "0",
            "tier": 0
        },
        // ...
    ]
}

// GET /api/plan/:planId
// 返回单个套餐详情
```

#### 5.1.2 流量查询
```javascript
// GET /api/traffic/:identityAddress
// 返回流量使用情况
{
    "identityAddress": "0x...",
    "trafficUsedDaily": "52428800",      // 50 MB
    "trafficLimitDaily": "104857600",    // 100 MB
    "trafficUsedMonthly": "10737418240", // 10 GB
    "trafficLimitMonthly": "107374182400", // 100 GB
    "dailyRemaining": "52428800",
    "monthlyRemaining": "96636764160",
    "isSuspended": false,
    "nextResetDaily": "2026-04-14T00:00:00Z",
    "nextResetMonthly": "2026-05-01T00:00:00Z"
}
```

#### 5.1.3 订阅变更
```javascript
// POST /api/subscription/upgrade
// 升级订阅
{
    "identityAddress": "0x...",
    "newPlanId": 3,
    "isYearly": false,
    "signature": "0x...",
    "permitSignature": "0x..."
}

// POST /api/subscription/downgrade
// 降级订阅
{
    "identityAddress": "0x...",
    "newPlanId": 1,
    "signature": "0x..."
}

// POST /api/subscription/cancel-change
// 取消下周期变更
{
    "identityAddress": "0x...",
    "signature": "0x..."
}
```

### 5.2 流量追踪服务

```javascript
/**
 * 流量追踪服务
 * 定期从 VPN 服务器同步流量数据
 */
class TrafficTracker {
    constructor({ contractAddress, relayerAccount }) {
        this.contractAddress = contractAddress;
        this.relayerAccount = relayerAccount;
        this.checkIntervalSeconds = 300; // 5 分钟
    }
    
    async start() {
        setInterval(() => this.tick(), this.checkIntervalSeconds * 1000);
    }
    
    async tick() {
        // 1. 从 VPN 服务器获取流量数据
        const trafficData = await this.fetchTrafficFromVPN();
        
        // 2. 检查是否超限
        for (const { identityAddress, bytesUsed } of trafficData) {
            const subscription = await this.getSubscription(identityAddress);
            const plan = await this.getPlan(subscription.planId);
            
            // 检查日流量
            if (plan.trafficLimitDaily > 0) {
                const dailyUsed = subscription.trafficUsedDaily + bytesUsed;
                if (dailyUsed > plan.trafficLimitDaily) {
                    await this.suspendService(identityAddress);
                    console.log(`[${identityAddress}] 日流量超限,暂停服务`);
                }
            }
            
            // 检查月流量
            if (plan.trafficLimitMonthly > 0) {
                const monthlyUsed = subscription.trafficUsedMonthly + bytesUsed;
                if (monthlyUsed > plan.trafficLimitMonthly) {
                    await this.suspendService(identityAddress);
                    console.log(`[${identityAddress}] 月流量超限,暂停服务`);
                }
            }
            
            // 3. 上报流量到合约
            await this.reportTraffic(identityAddress, bytesUsed);
        }
        
        // 4. 检查是否需要重置流量
        await this.checkAndResetTraffic();
    }
    
    async suspendService(identityAddress) {
        // 调用合约暂停服务
        const calldata = iface.encodeFunctionData('suspendForTrafficLimit', [
            identityAddress
        ]);
        
        await sendTransactionViaCDP({
            account: this.relayerAccount,
            contractAddress: this.contractAddress,
            calldata
        });
    }
    
    async checkAndResetTraffic() {
        const now = Math.floor(Date.now() / 1000);
        const subscriptions = await this.getAllActiveSubscriptions();
        
        for (const sub of subscriptions) {
            // 检查日流量重置
            const daysSinceReset = Math.floor((now - sub.lastResetDaily) / 86400);
            if (daysSinceReset >= 1) {
                await this.resetDailyTraffic(sub.identityAddress);
            }
            
            // 检查月流量重置
            const monthsSinceReset = this.getMonthsDiff(
                new Date(sub.lastResetMonthly * 1000),
                new Date(now * 1000)
            );
            if (monthsSinceReset >= 1) {
                await this.resetMonthlyTraffic(sub.identityAddress);
            }
        }
    }
}
```

---

## 6. 数据库设计

### 6.1 流量记录表

```sql
CREATE TABLE traffic_usage (
    id BIGSERIAL PRIMARY KEY,
    identity_address VARCHAR(42) NOT NULL,
    bytes_used BIGINT NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT NOW(),
    reset_type VARCHAR(10), -- 'daily' or 'monthly'
    INDEX idx_identity_time (identity_address, timestamp)
);

CREATE TABLE traffic_summary (
    identity_address VARCHAR(42) PRIMARY KEY,
    daily_used BIGINT NOT NULL DEFAULT 0,
    monthly_used BIGINT NOT NULL DEFAULT 0,
    last_reset_daily TIMESTAMP NOT NULL,
    last_reset_monthly TIMESTAMP NOT NULL,
    is_suspended BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

### 6.2 订阅变更记录表

```sql
CREATE TABLE subscription_changes (
    id BIGSERIAL PRIMARY KEY,
    identity_address VARCHAR(42) NOT NULL,
    from_plan_id INT NOT NULL,
    to_plan_id INT NOT NULL,
    change_type VARCHAR(20) NOT NULL, -- 'upgrade', 'downgrade', 'cancel'
    effective_at TIMESTAMP NOT NULL,
    proration_amount VARCHAR(20), -- USDC amount
    tx_hash VARCHAR(66),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    INDEX idx_identity (identity_address),
    INDEX idx_effective (effective_at)
);
```

---

## 7. 前端界面设计

### 7.1 套餐选择界面

```html
<div class="pricing-tiers">
    <div class="tier free">
        <h3>免费版</h3>
        <div class="price">$0 / 月</div>
        <ul class="features">
            <li>✅ 每日 100MB 流量</li>
            <li>✅ 基础服务器</li>
            <li>❌ 无月流量限制</li>
        </ul>
        <button onclick="subscribe(1, false)">选择免费版</button>
    </div>
    
    <div class="tier basic">
        <h3>基础版</h3>
        <div class="price">$5 / 月</div>
        <ul class="features">
            <li>✅ 每月 100GB 流量</li>
            <li>✅ 标准服务器</li>
            <li>✅ 按年付享 8.3 折</li>
        </ul>
        <button onclick="subscribe(2, false)">按月订阅</button>
        <button onclick="subscribe(2, true)">按年订阅 ($50/年)</button>
    </div>
    
    <div class="tier premium">
        <h3>高级版</h3>
        <div class="price">$10 / 月</div>
        <ul class="features">
            <li>✅ 无限流量</li>
            <li>✅ 高速服务器</li>
            <li>✅ 按年付享 8.3 折</li>
        </ul>
        <button onclick="subscribe(3, false)">按月订阅</button>
        <button onclick="subscribe(3, true)">按年订阅 ($100/年)</button>
    </div>
</div>
```

### 7.2 流量使用显示

```html
<div class="traffic-usage">
    <h4>流量使用情况</h4>
    
    <div class="daily-usage">
        <label>今日流量:</label>
        <div class="progress-bar">
            <div class="progress" style="width: 50%"></div>
        </div>
        <span>50 MB / 100 MB</span>
        <span class="reset-time">重置时间: 今晚 00:00</span>
    </div>
    
    <div class="monthly-usage">
        <label>本月流量:</label>
        <div class="progress-bar">
            <div class="progress" style="width: 10%"></div>
        </div>
        <span>10 GB / 100 GB</span>
        <span class="reset-time">重置时间: 2026-05-01</span>
    </div>
</div>
```

### 7.3 订阅变更界面

```html
<div class="subscription-change">
    <h4>变更订阅</h4>
    
    <div class="current-plan">
        <label>当前套餐:</label>
        <span>基础版 ($5/月)</span>
    </div>
    
    <div class="upgrade-option">
        <label>升级到高级版:</label>
        <p>立即生效,补差价: $3.50</p>
        <button onclick="upgrade(3)">立即升级</button>
    </div>
    
    <div class="downgrade-option">
        <label>降级到免费版:</label>
        <p>下周期生效 (2026-05-01)</p>
        <button onclick="downgrade(1)">下周期降级</button>
    </div>
    
    <div class="pending-change" v-if="hasPendingChange">
        <label>待生效变更:</label>
        <span>降级到免费版 (2026-05-01 生效)</span>
        <button onclick="cancelChange()">取消变更</button>
    </div>
</div>
```

---

## 8. 实施计划

### 8.1 Phase 1: 合约升级 (3-5 天)
- [ ] 设计并实现新的 Plan 结构
- [ ] 添加流量管理函数
- [ ] 实现 Proration 算法
- [ ] 添加订阅变更函数
- [ ] 编写单元测试
- [ ] 部署到测试网

### 8.2 Phase 2: 后端开发 (5-7 天)
- [ ] 设计数据库表结构
- [ ] 实现流量追踪服务
- [ ] 实现套餐管理 API
- [ ] 实现订阅变更 API
- [ ] 集成 VPN 服务器流量上报
- [ ] 编写集成测试

### 8.3 Phase 3: 前端开发 (3-5 天)
- [ ] 设计套餐选择界面
- [ ] 实现流量使用显示
- [ ] 实现订阅变更界面
- [ ] 集成后端 API
- [ ] 用户体验优化

### 8.4 Phase 4: 集成测试 (2-3 天)
- [ ] 端到端测试
- [ ] 性能测试
- [ ] 安全审计
- [ ] Bug 修复

### 8.5 Phase 5: 上线部署 (1-2 天)
- [ ] 主网部署
- [ ] 数据迁移
- [ ] 监控配置
- [ ] 文档更新

**总计**: 14-22 天

---

## 9. 风险评估

### 9.1 技术风险
- **流量追踪准确性**: VPN 服务器流量统计可能不准确
  - 缓解: 多点验证,异常检测
- **Proration 计算精度**: Solidity 整数运算可能有精度损失
  - 缓解: 使用更高精度,四舍五入规则
- **Gas 成本**: 频繁的流量上报可能导致高 Gas 费
  - 缓解: 批量上报,链下追踪

### 9.2 业务风险
- **用户体验**: 流量限制可能导致用户不满
  - 缓解: 清晰的流量提醒,平滑的升级路径
- **定价策略**: 套餐价格可能不合理
  - 缓解: 市场调研,灵活调整
- **迁移成本**: 现有用户迁移到新系统
  - 缓解: 平滑迁移方案,保留旧订阅

---

## 10. 后续优化方向

### 10.1 短期优化 (1-3 个月)
- 流量使用分析和可视化
- 套餐推荐算法
- 自动升级提醒

### 10.2 中期优化 (3-6 个月)
- 动态定价 (根据市场需求)
- 流量包购买 (一次性流量)
- 多设备支持

### 10.3 长期优化 (6-12 个月)
- 企业版套餐
- API 访问
- 白标解决方案

---

## 11. 总结

本重构方案实现了完整的订阅分级系统,包括:
1. ✅ 三级套餐体系 (Free/Basic/Premium)
2. ✅ 流量限制和追踪
3. ✅ Proration 算法
4. ✅ 订阅变更管理
5. ✅ 完整的前后端实现

**核心优势**:
- 灵活的定价策略
- 公平的按比例计费
- 良好的用户体验
- 可扩展的架构

**下一步**: 开始 Phase 1 合约升级开发

---

**文档版本**: V1.0  
**最后更新**: 2026-04-13 14:20  
**作者**: Claude Code  
**审核状态**: 待审核
