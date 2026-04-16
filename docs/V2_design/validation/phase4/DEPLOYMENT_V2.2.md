# VPNSubscription V2.2 部署与验证状态

> 部署日期: 2026-04-16  
> 文档状态: 基于本轮真实链上验证更新  
> 当前网络: Base Sepolia

---

## 1. 当前有效部署

### 合约地址
`0xAAe4ebc1557a4bA66FCE1E55d495B7EACdf58297`

### 关键运行地址
- Payer / 测试钱包: `0x490DC2F60aececAFF22BC670166cbb9d5DdB9241`
- 测试 identity: `0x729e71ff357ccefAa31635931621531082A698f6`
- Runtime Smart Account / Relayer: `0x10AB796695843043CF303Cc8C7a58E9498023768`
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

### 区块浏览器
https://sepolia.basescan.org/address/0xAAe4ebc1557a4bA66FCE1E55d495B7EACdf58297

---

## 2. 合约层确认

本轮部署的 V2.2 合约保留了以下关键设计：

- 移除 `isActive`
- 订阅有效性由 `expiresAt` 和 `isSuspended` 共同决定
- 自动续费通过 `executeRenewal(address)` 执行
- 续费成功后更新：
  - `renewedAt`
  - `expiresAt`
  - `nextRenewalAt`

测试套餐（planId = 4）参数：
- 价格: `0.1 USDC`
- 周期: `1800s`（30 分钟）

---

## 3. 本轮已确认可用的能力

### 3.1 免 gas 首次订阅
已验证成功。

表现：
- 前端可发起订阅
- 后端通过 CDP Smart Account + Paymaster 发送 UserOperation
- 链上成功扣除 0.1 USDC
- 订阅状态可查询

### 3.2 免 gas 自动续费
已验证成功。

已观察到至少两笔链上自动续费扣款：
- `0x3f8c0bb6119e7f9804e628f32bc228871927a4fb13991241b694abc09196c434`
- `0x7105d5fb85d68bcc07f28d734da485212086fdab39e42e4e4159efdc3f92ce32`

说明：
- 自动续费链路已经真实打通
- 不是停留在静态代码“看起来可以”
- 是已经在 Base Sepolia 上完成了真实扣款验证

### 3.3 relayer 一致性校验
已验证成功。

后端启动时已增加 fail-fast 校验：
- 链上 `relayer()`
- 当前运行中的 Smart Account

若不一致，服务应直接拒绝启动。

---

## 4. 本轮已修复的问题

### 4.1 relayer 不一致导致订阅失败
现象：
- `VPN: not relayer`

修复：
- 更新链上 relayer
- 启动时增加一致性校验

### 4.2 后端订阅结构索引漂移
现象：
- `/api/subscription/:address` 返回 500
- 前端订阅后状态不刷新

修复：
- 按 V2.2 的 `Subscription` 新结构修正索引
- 所有 BigInt 输出统一转字符串

### 4.3 自动续费服务误判订阅已暂停
现象：
- 日志持续输出 `订阅已暂停,跳过`
- 但链上实际订阅并未暂停

根因：
- `renewal-service.js` 继续使用旧结构体索引

修复：
- 修正 `autoRenewEnabled` 和 `isSuspended` 索引
- 修正 `precheck` 读取的到期字段索引

### 4.4 流量上报发送参数错误
现象：
- `Cannot read properties of undefined (reading 'address')`

根因：
- `traffic-tracker.js` 调用 `sendTransactionViaCDP(...)` 时参数名与实现不一致

修复：
- 统一为 `account / contractAddress / calldata / network`

---

## 5. 关于“是否存在重复扣款 bug”的当前判断

当前没有证据表明存在“短时间内重复自动续费”的新 bug。

链上与日志对照后的判断是：
- 首次订阅后，第一次自动续费曾经因为旧 bug 延迟触发
- 修复后，续费时间重新回到正常的 30 分钟周期窗口
- 后续扣款符合链上 `nextRenewalAt` 条件，不是提前重复扣款

为了后续排查更直接，`renewal-service.js` 已补充详细时间日志，包含：
- `now`
- `start`
- `renewedAt`
- `expiresAt`
- `nextRenewalAt`
- `lockedPeriod`
- `timeUntilExpiry`
- `timeUntilNextRenewal`

---

## 6. 当前仍需继续观察的事项

### 6.1 下一轮自动续费
当前最重要的观察点：
- 下一轮 0.1 USDC 是否在预期窗口内再次成功扣费
- 续费前后的日志时间字段是否与链上记录一致

### 6.2 流量上报功能
代码侧已修复调用参数错误。
仍需通过重启后的真实运行日志再次确认没有新报错。

---

## 7. 建议的留档结论

截至当前，Phase 4 可以保留的事实性结论是：

- 免 gas 首次订阅：已实现，并已链上验证
- 免 gas 自动续费：已实现，并已链上验证
- relayer 校验：已补强
- 订阅状态查询链路：已修复
- 自动续费日志：已增强，可继续用于后续核对

不应再保留那些基于旧静态审查、且结论为“自动续费尚未打通”的阶段性文档，因为它们已经与当前真实状态不一致。
