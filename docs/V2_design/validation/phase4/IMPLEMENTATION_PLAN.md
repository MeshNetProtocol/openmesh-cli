# v2.1 实施计划

> **文档版本**: v1.0  
> **创建日期**: 2026-04-15  
> **对应设计**: SIMPLIFIED_SUBSCRIPTION_DESIGN.md v2.1

---

## 一、实施目标

将当前混合实现（前端生成 12 个 EIP-3009 签名但后端未使用）改造为 v2.1 设计方案：
- 用户订阅时签名 2 次（SubscribeIntent + EIP-2612 Permit）
- 授权额度为 `type(uint256).max`（无限额）
- 后端通过链上事件维护订阅列表
- 取消订阅时引导用户 revoke allowance

---

## 二、文件修改清单

### 2.1 前端修改 (frontend/app.js)

**当前问题**：
1. 存在 `generateEIP3009Signatures` 函数（lines 441-519），生成 12 个 EIP-3009 签名但从未被后端使用
2. `maxAmount` 计算逻辑为 `price * 12`（月付）或 `price * 1`（年付），导致 12 个月后 allowance 耗尽
3. UI 文案未区分两步签名，用户不清楚每次弹窗的用途
4. 取消订阅后未引导用户 revoke allowance

**修改内容**：

#### 修改 1：移除 EIP-3009 签名生成逻辑
- **位置**: lines 441-519
- **操作**: 删除整个 `generateEIP3009Signatures` 函数
- **原因**: 后端从未存储和使用这些签名，完全是冗余操作

#### 修改 2：修正 maxAmount 计算逻辑
- **位置**: `subscribe()` 函数中的 `maxAmount` 计算部分
- **当前代码**:
  ```javascript
  const monthsToAuthorize = 12;
  const maxAmount = isYearly 
    ? (price * 1).toString()
    : (price * monthsToAuthorize).toString();
  ```
- **修改为**:
  ```javascript
  // 授权额度：无限额
  // 安全边界由合约 executeRenewal 保证，每次只扣 lockedPrice
  const maxAmount = ethers.MaxUint256.toString();
  ```
- **原因**: 避免 12 个月后 allowance 耗尽导致续费中断

#### 修改 3：更新 UI 文案，区分两步签名
- **位置**: `subscribe()` 函数中的两次 `signTypedData` 调用前
- **当前代码**:
  ```javascript
  showStatus('正在签名订阅意图...', 'info');
  // ... 第 1 次签名 ...
  
  showStatus('正在签名 USDC 授权...', 'info');
  // ... 第 2 次签名 ...
  ```
- **修改为**:
  ```javascript
  showStatus('第 1/2 步：签名订阅意图...', 'info');
  // ... 第 1 次签名 ...
  
  showStatus('第 2/2 步：签名 USDC 授权（此后自动续费无需再次操作）...', 'info');
  // ... 第 2 次签名 ...
  ```
- **原因**: 让用户清楚知道需要签名 2 次，以及第 2 次签名的长期效果

#### 修改 4：取消订阅时引导用户 revoke allowance
- **位置**: `cancelSubscription()` 函数的成功回调部分
- **当前代码**:
  ```javascript
  showStatus('订阅已取消', 'success');
  setTimeout(refresh, 2000);
  ```
- **修改为**:
  ```javascript
  showStatus(
    '订阅已取消。如需彻底撤销 USDC 授权，请访问 revoke.cash 或在钱包中将合约授权归零。',
    'info'
  );
  setTimeout(refresh, 2000);
  ```
- **原因**: 提醒用户取消订阅后 allowance 仍然存在，需要主动 revoke

---

### 2.2 后端修改 (subscription-service/index.js)

**当前问题**：
1. 使用手工维护的 `subscriptionList`，来源不明，存在链上/链下状态不一致风险
2. 缺少链上事件监听机制
3. 服务重启后 `subscriptionList` 丢失，无恢复机制

**修改内容**：

#### 修改 1：移除手工维护的 subscriptionList
- **位置**: 当前代码中 `subscriptionList` 的初始化和手工添加/删除逻辑
- **操作**: 删除所有手工维护代码
- **原因**: 改为事件驱动方式，链上事件是唯一可信来源

#### 修改 2：添加链上事件监听
- **位置**: 服务启动时，在定时任务之前
- **新增代码**:
  ```javascript
  // 初始化合约实例（用于事件监听）
  const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
  
  // 订阅列表（内存 + 持久化）
  const subscriptionSet = new Set();
  
  // 监听新增订阅
  contract.on('Subscribed', (identityAddress, user, planId, expiresAt) => {
    console.log(`✅ 新订阅: ${identityAddress}`);
    subscriptionSet.add(identityAddress);
    // TODO: 持久化到数据库（可选）
  });
  
  // 监听取消订阅
  contract.on('SubscriptionCancelled', (identityAddress) => {
    console.log(`❌ 订阅取消: ${identityAddress}`);
    subscriptionSet.delete(identityAddress);
    // TODO: 从数据库删除（可选）
  });
  
  // 监听续费失败
  contract.on('RenewalFailed', (identityAddress, reason) => {
    console.error(`⚠️ 续费失败: ${identityAddress}, 原因: ${reason}`);
    // TODO: 通知用户（邮件/Push）
  });
  ```
- **原因**: 链上事件是订阅状态的唯一可信来源

#### 修改 3：添加服务启动时的链上历史同步
- **位置**: 服务启动时，在事件监听器注册之后
- **新增代码**:
  ```javascript
  // 服务启动时从链上同步历史订阅
  async function syncFromChain() {
    console.log('🔄 从链上同步订阅列表...');
    
    const DEPLOY_BLOCK = 19000000; // TODO: 替换为合约实际部署区块
    const filter = contract.filters.Subscribed();
    const events = await contract.queryFilter(filter, DEPLOY_BLOCK, 'latest');
    
    for (const event of events) {
      subscriptionSet.add(event.args.identityAddress);
    }
    
    console.log(`✅ 已从链上同步 ${subscriptionSet.size} 个订阅`);
  }
  
  // 启动时执行同步
  syncFromChain().catch(console.error);
  ```
- **原因**: 防止服务重启后订阅列表丢失

#### 修改 4：更新定时任务，使用 subscriptionSet
- **位置**: 定时任务的 `for` 循环
- **当前代码**:
  ```javascript
  for (const identityAddress of subscriptionList) {
  ```
- **修改为**:
  ```javascript
  for (const identityAddress of subscriptionSet) {
  ```
- **原因**: 使用事件驱动维护的订阅列表

---

### 2.3 合约修改 (contracts/src/VPNSubscriptionV2.sol)

**结论**: **无需修改**

**原因**:
- 合约已支持 `permitAndSubscribe`（EIP-2612 主订阅入口）
- 合约已支持 `executeRenewal`（自动续费，依赖 allowance）
- 合约已支持 `cancelFor`（取消自动续费）
- 合约已有 `Subscribed`、`SubscriptionCancelled`、`RenewalFailed` 事件
- 合约的 `lockedPrice` 和 `lockedPeriod` 机制已支持价格锁定

---

## 三、实施步骤

### 阶段 1：前端修改（预计 30 分钟）
1. ✅ 删除 `generateEIP3009Signatures` 函数
2. ✅ 修改 `maxAmount` 为 `ethers.MaxUint256`
3. ✅ 更新两次签名的 UI 文案
4. ✅ 添加取消订阅后的 revoke 引导

### 阶段 2：后端修改（预计 45 分钟）
1. ✅ 移除手工维护的 `subscriptionList`
2. ✅ 添加链上事件监听（`Subscribed`、`SubscriptionCancelled`、`RenewalFailed`）
3. ✅ 添加 `syncFromChain()` 函数
4. ✅ 更新定时任务使用 `subscriptionSet`

### 阶段 3：测试验证（预计 1 小时）
1. ✅ 测试订阅流程（2 次 MetaMask 弹窗）
2. ✅ 验证 `maxAmount` 为无限额
3. ✅ 测试自动续费（模拟时间跳过 30 天）
4. ✅ 测试 12 个月后续费（验证无限额不中断）
5. ✅ 测试取消订阅 + revoke 引导
6. ✅ 测试年付优惠价格锁定
7. ✅ 测试服务重启后订阅列表恢复

---

## 四、测试用例

### 4.1 订阅流程测试

**测试目标**: 验证用户签名 2 次，授权额度为无限额

**步骤**:
1. 打开前端，连接钱包
2. 选择套餐（月付或年付）
3. 点击订阅
4. 观察 MetaMask 弹窗次数（应为 2 次）
5. 第 1 次弹窗：SubscribeIntent 签名
6. 第 2 次弹窗：EIP-2612 Permit 签名
7. 检查链上 USDC allowance：`usdc.allowance(userAddress, contractAddress)`

**预期结果**:
- MetaMask 弹出 2 次
- UI 显示 "第 1/2 步" 和 "第 2/2 步"
- 链上 allowance 为 `type(uint256).max`（或接近该值）

---

### 4.2 自动续费测试

**测试目标**: 验证到期后自动续费成功

**步骤**:
1. 订阅月付套餐
2. 修改合约中的 `expiresAt` 为当前时间 - 1 天（或等待 30 天）
3. 等待后端定时任务触发（60 秒内）
4. 检查链上订阅状态：`contract.subscriptions(identityAddress)`

**预期结果**:
- 后端日志显示 "✅ 自动续费成功"
- `expiresAt` 延长了 30 天
- 用户 USDC 余额减少 `lockedPrice`

---

### 4.3 12 个月后续费测试

**测试目标**: 验证无限额 allowance 不会在 12 个月后中断

**步骤**:
1. 订阅月付套餐
2. 模拟 12 次自动续费（修改 `expiresAt` 12 次）
3. 检查第 13 次续费是否成功

**预期结果**:
- 第 13 次续费成功
- allowance 仍然充足（`type(uint256).max` 减去 13 个月的费用）

---

### 4.4 取消订阅测试

**测试目标**: 验证取消后引导用户 revoke allowance

**步骤**:
1. 订阅任意套餐
2. 点击取消订阅
3. 观察 UI 提示

**预期结果**:
- UI 显示 "订阅已取消。如需彻底撤销 USDC 授权，请访问 revoke.cash 或在钱包中将合约授权归零。"
- 链上 `autoRenewEnabled` 为 `false`
- allowance 仍然存在（需用户手动 revoke）

---

### 4.5 服务重启测试

**测试目标**: 验证服务重启后订阅列表恢复

**步骤**:
1. 创建 3 个订阅
2. 重启后端服务
3. 检查后端日志

**预期结果**:
- 日志显示 "🔄 从链上同步订阅列表..."
- 日志显示 "✅ 已从链上同步 3 个订阅"
- 定时任务正常触发续费

---

### 4.6 年付优惠测试

**测试目标**: 验证年付价格锁定

**步骤**:
1. 订阅年付套餐（假设 10 USDC/年）
2. 管理员修改套餐价格为 15 USDC/年
3. 等待 1 年后自动续费
4. 检查扣款金额

**预期结果**:
- 第 1 年扣款 10 USDC
- 第 2 年续费仍扣款 10 USDC（不受涨价影响）

---

## 五、风险评估

### 5.1 无限额 Allowance 风险

**风险**: 合约如果有漏洞，理论上可以取走用户全部 USDC

**缓解措施**:
- `executeRenewal` 每次只 `transferFrom` `lockedPrice`，金额写死在合约存储中
- 合约不是可升级合约，逻辑不会被替换
- 建议上线前进行合约审计
- 用户可随时调用 `usdc.approve(contractAddress, 0)` 完全撤销

**结论**: 风险等级与 Uniswap、Aave 等主流 DeFi 协议相当，可接受

---

### 5.2 续费失败风险（用户 USDC 余额不足）

**场景**: 到期时用户钱包 USDC 余额 < `lockedPrice`

**处理**:
- 合约 `executeRenewal` revert，emit `RenewalFailed`
- 后端事件监听器捕获，向用户发送通知（邮件/Push）
- 用户充值后，后端在下一次定时任务中重试

**建议**: 合约支持宽限期（3 天），在宽限期内允许重试

---

### 5.3 取消订阅后 Allowance 残留

**场景**: 用户调用 `cancelFor` 后，USDC allowance 仍然存在

**说明**:
- 合约无法主动撤销 USDC 合约中的 allowance（跨合约操作限制）
- 取消后后端停止调用 `executeRenewal`，allowance 不会被消耗
- 但如果合约将来有漏洞，残留 allowance 仍是风险

**处理**:
- 前端取消成功后，弹出提示引导用户手动 revoke
- 可提供 revoke.cash 链接或直接调用 USDC `approve(contract, 0)`
- 这一步为可选操作，但推荐用户执行

---

### 5.4 服务重启后订阅列表丢失

**场景**: 后端服务重启，内存中的 `subscriptionSet` 清空

**处理**:
- 服务启动时调用 `syncFromChain()`，从合约部署区块开始重建列表
- 同时将列表持久化到本地数据库，作为缓存层，减少启动时的 RPC 查询量

---

## 六、回滚计划

如果实施过程中发现严重问题，可按以下步骤回滚：

1. **前端回滚**: 恢复 `generateEIP3009Signatures` 函数，恢复 `maxAmount` 计算逻辑
2. **后端回滚**: 恢复手工维护的 `subscriptionList`，移除事件监听
3. **合约无需回滚**: 合约同时支持 EIP-3009 和 EIP-2612，不影响已有订阅

---

## 七、上线检查清单

- [ ] 前端修改完成并通过本地测试
- [ ] 后端修改完成并通过本地测试
- [ ] 所有测试用例通过
- [ ] 合约审计完成（如需要）
- [ ] 更新用户文档（说明 2 次签名和 revoke 流程）
- [ ] 准备回滚方案
- [ ] 监控告警配置（续费失败、事件监听异常）
- [ ] 灰度发布（先在测试网验证 1 周）

---

## 八、后续优化

1. **持久化订阅列表**: 将 `subscriptionSet` 持久化到 PostgreSQL/Redis，减少服务重启时的链上查询
2. **续费失败通知**: 集成邮件/Push 通知服务，在 `RenewalFailed` 时通知用户
3. **宽限期支持**: 合约增加 3 天宽限期，允许用户在到期后 3 天内充值并重试
4. **一键 Revoke**: 前端提供一键撤销 allowance 的按钮，无需用户手动去 revoke.cash
5. **监控面板**: 添加 Grafana 面板，监控订阅数量、续费成功率、失败原因分布

---

## 九、总结

本实施计划将当前混合实现改造为 v2.1 设计方案，核心改动：
- 前端：移除 12 个 EIP-3009 签名，改为无限额 EIP-2612 授权
- 后端：移除手工维护列表，改为链上事件驱动
- 合约：无需修改

预计总工时：2-3 小时（开发 + 测试）

风险可控，回滚方案明确，建议按阶段推进。
