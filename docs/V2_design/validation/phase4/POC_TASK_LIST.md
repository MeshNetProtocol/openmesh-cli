# VPN 订阅支付 PoC 工作清单

**基于**: usdc_subscription_payment_v3.md 设计文档  
**当前状态**: Phase 4 基础框架已完成,需要对齐 V3.3 设计方案  
**创建日期**: 2026-04-10

---

## 已完成的工作 ✅

### 环境配置
- ✅ CDP API 配置完成 (.env 文件)
  - CDP_API_KEY_ID 和 CDP_API_KEY_SECRET 已配置
  - CDP_WALLET_SECRET 已配置
  - SERVICE_WALLET_ADDRESS 已设置
- ✅ 网络配置: Base Sepolia
- ✅ 订阅价格配置: 1.00 USDC

### 后端服务 (auth-service)
- ✅ Go 项目结构搭建完成
- ✅ CDP 客户端基础实现 (cdp_client.go)
  - VerifyX402Payment
  - CreateSpendPermission
  - ExecuteSpendPermission
  - GetSpendPermissionStatus
  - GetTransactionDetails
- ✅ 主服务实现 (main.go)
  - POST /poc/subscriptions - 创建订阅
  - POST /poc/subscriptions/{order_id}/activate - 激活订阅
  - POST /poc/subscriptions/query - 查询订阅
  - POST /poc/subscriptions/cancel - 取消订阅
  - POST /poc/auto-renew/setup - 配置自动续费
  - POST /poc/auto-renew/{identity}/trigger - 触发续费
  - GET /poc/config - 获取配置
- ✅ 数据持久化 (JSON 文件)
  - subscription_requests.json
  - payments.json
  - auto_renew_profiles.json

### 前端页面
- ✅ 订阅支付页面 (web/subscribe.html)
  - MetaMask 连接
  - 网络检测 (Base Sepolia)
  - USDC 余额检查
  - USDC 转账支付
  - 订阅激活

### 测试脚本
- ✅ start.sh - 启动服务脚本
- ✅ mac_client_simulator.sh - Mac 客户端模拟器
- ✅ test_one_time_payment.sh - 一次性支付测试
- ✅ test_auto_renewal.sh - 自动续费测试
- ✅ test_subscription.sh - 完整订阅流程测试
- ✅ test_subscription_management.sh - 订阅管理测试

---

## 需要完成的工作 (对齐 V3.3 设计)

### 🔴 P0: 核心功能缺失 (阻塞 PoC)

#### 1. 智能合约开发与部署
**当前状态**: 完全缺失  
**需要完成**:
- [ ] 创建 Foundry 项目
- [ ] 实现 VPNSubscription.sol 合约
  - [ ] EIP-712 domain 和 type hashes (SubscribeIntent, CancelIntent)
  - [ ] permitAndSubscribe 函数
  - [ ] executeRenewal 函数
  - [ ] cancelFor 函数 (EIP-712 签名验证)
  - [ ] finalizeExpired 函数
  - [ ] 事件定义
- [ ] 编写单元测试 (覆盖率 > 95%)
- [ ] 部署到 Base Sepolia
- [ ] 在 BaseScan 验证合约

#### 2. 前端 EIP-712 签名实现
**当前状态**: 前端只实现了简单的 USDC 转账,缺少 EIP-712 签名  
**需要完成**:
- [ ] 安装 viem 依赖
- [ ] 实现 SubscribeIntent EIP-712 签名
  - [ ] domain 配置
  - [ ] types 定义
  - [ ] signTypedData 调用
- [ ] 实现 ERC-2612 permit 签名
  - [ ] permitAmount 计算 (按 planId 映射)
  - [ ] USDC permit domain 配置
- [ ] 实现 CancelIntent EIP-712 签名
- [ ] 修改订阅流程: 双签名 → 后端调用合约

#### 3. 后端合约集成
**当前状态**: 后端使用 Spend Permission,需要改为调用智能合约  
**需要完成**:
- [ ] 集成 CDP Server Wallet SDK (替换当前的 CDP Client)
- [ ] 实现合约调用
  - [ ] permitAndSubscribe (通过 CDP Server Wallet)
  - [ ] executeRenewal
  - [ ] cancelFor
  - [ ] finalizeExpired
- [ ] 实现 EIP-712 签名离链验证
  - [ ] SubscribeIntent 验证
  - [ ] CancelIntent 验证
- [ ] 实现 IdempotencyKey 幂等机制
- [ ] 实现 nonce 管理 (intentNonces, cancelNonces)

#### 4. 链上事件监听
**当前状态**: 完全缺失  
**需要完成**:
- [ ] 实现事件监听服务
  - [ ] SubscriptionCreated
  - [ ] SubscriptionRenewed
  - [ ] SubscriptionCancelled
  - [ ] RenewalFailed
  - [ ] SubscriptionExpired
  - [ ] SubscriptionForceClosed
- [ ] 事件处理逻辑
  - [ ] 更新数据库状态
  - [ ] 触发 Xray 操作 (添加/删除用户)

---

### 🟡 P1: 重要功能 (PoC 完整性)

#### 5. 定时任务实现
**当前状态**: 缺失  
**需要完成**:
- [ ] 到期前 24h 预检任务
  - [ ] 查询即将到期的订阅
  - [ ] 预检 allowance/balance
  - [ ] 发送余额不足提醒
- [ ] 到期后续费任务
  - [ ] 查询已到期订阅
  - [ ] 幂等锁 (userAddress + expiresAt)
  - [ ] 调用 executeRenewal
  - [ ] 失败计数 (DB failCount++)
- [ ] 强制停服任务
  - [ ] failCount >= 3 时停服
  - [ ] 调用 finalizeExpired(user, true)
- [ ] 自然到期清理任务
  - [ ] 已取消且到期的订阅
  - [ ] 调用 finalizeExpired(user, false)

#### 6. 数据库改造
**当前状态**: 使用 JSON 文件,需要改为真实数据库  
**需要完成**:
- [ ] 选择数据库 (SQLite/PostgreSQL)
- [ ] 设计 schema
  - [ ] subscriptions 表 (含 identityAddress 唯一索引)
  - [ ] payments 表
  - [ ] idempotency_keys 表
  - [ ] renewal_fail_count 字段
- [ ] 实现数据访问层
- [ ] 迁移现有 JSON 数据

#### 7. CDP Paymaster 配置
**当前状态**: 未配置  
**需要完成**:
- [ ] 配置 Paymaster endpoint
- [ ] 设置合约白名单 (VPNSubscription 合约地址)
- [ ] 设置允许的方法 (permitAndSubscribe, executeRenewal, cancelFor, finalizeExpired)
- [ ] 设置月度上限 ($50)
- [ ] 测试 gas 赞助功能

---

### 🟢 P2: 优化与完善 (生产准备)

#### 8. 监控与告警
- [ ] Prometheus metrics 实现
- [ ] 告警规则配置
- [ ] 日志优化

#### 9. 错误处理与重试
- [ ] CDP API 调用重试机制
- [ ] 链上交易失败处理
- [ ] 事件监听重试

#### 10. 测试完善
- [ ] 端到端测试
- [ ] 并发测试
- [ ] 异常场景测试

#### 11. 文档更新
- [ ] 更新 README.md (对齐 V3.3 方案)
- [ ] API 文档
- [ ] 部署文档

---

## 当前架构 vs V3.3 设计的差异

| 功能 | 当前实现 | V3.3 设计 | 需要改动 |
|------|---------|-----------|---------|
| 支付方式 | 直接 USDC 转账 | EIP-712 SubscribeIntent + permit | ✅ 需要重构 |
| 合约 | 无 | VPNSubscription.sol | ✅ 需要开发 |
| 自动续费 | Spend Permission | 合约 executeRenewal | ✅ 需要改造 |
| 取消订阅 | 简单状态更新 | EIP-712 CancelIntent + cancelFor | ✅ 需要重构 |
| Gas 赞助 | 未实现 | CDP Paymaster | ✅ 需要配置 |
| 事件监听 | 无 | 完整事件监听 | ✅ 需要开发 |
| 数据存储 | JSON 文件 | 数据库 | ⚠️ 建议改造 |
| 定时任务 | 无 | 预检/续费/停服/对账 | ✅ 需要开发 |

---

## 开发优先级建议

### 第一阶段 (Week 1): 合约 + 前端签名
1. 开发并部署智能合约
2. 前端实现 EIP-712 双签名
3. 验证签名流程端到端可用

### 第二阶段 (Week 2): 后端合约集成
1. 后端集成 CDP Server Wallet
2. 实现合约调用逻辑
3. 实现链上事件监听
4. 测试完整订阅流程

### 第三阶段 (Week 3): 自动续费
1. 实现定时任务
2. 实现续费逻辑
3. 实现停服逻辑
4. 测试自动续费流程

### 第四阶段 (Week 4): 完善与测试
1. 数据库改造
2. 监控告警
3. 端到端测试
4. 文档更新

---

## 快速启动 (当前版本)

```bash
# 1. 启动服务
cd auth-service
go run .

# 2. 模拟 Mac 客户端
./mac_client_simulator.sh 0x1234567890123456789012345678901234567890

# 3. 在浏览器中完成支付

# 4. 测试订阅管理
./test_subscription_management.sh 0x1234567890123456789012345678901234567890
```

---

## 参考资料

- [V3.3 设计文档](usdc_subscription_payment_v3.md)
- [CDP Paymaster 文档](https://docs.cdp.coinbase.com/paymaster/introduction/welcome)
- [CDP Server Wallets 文档](https://docs.cdp.coinbase.com/wallets/server-wallets)
- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-2612 Permit 规范](https://eips.ethereum.org/EIPS/eip-2612)

---

**最后更新**: 2026-04-10  
**状态**: Phase 4 基础框架完成,需要对齐 V3.3 设计方案
