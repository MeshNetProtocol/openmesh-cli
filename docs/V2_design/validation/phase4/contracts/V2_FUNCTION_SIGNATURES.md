# VPNSubscription V2 合约函数签名

## 概述

本文档详细说明 VPNSubscription V2 合约的所有函数签名，用于：
- CDP Paymaster 白名单配置
- 后端 API 集成
- 前端交互
- 其他开发模块理解合约接口

**合约地址**: `0x16D6D1564942798720CB69a6814bc2C53ECe23a1` (Base Sepolia)

**版本**: V2 (支持一个钱包为多个 VPN 身份订阅)

---

## CDP Paymaster 配置

### 需要赞助的函数签名（逗号分隔）

```
permitAndSubscribe(address,address,uint256,uint256,uint256,uint256,bytes,uint8,bytes32,bytes32),executeRenewal(address),cancelFor(address,address,uint256,bytes),finalizeExpired(address,bool)
```

---

## 核心函数详细说明

### 1. `permitAndSubscribe` - 订阅函数

**函数签名**:
```solidity
permitAndSubscribe(address,address,uint256,uint256,uint256,uint256,bytes,uint8,bytes32,bytes32)
```

**完整声明**:
```solidity
function permitAndSubscribe(
    address user,              // 付款钱包地址
    address identityAddress,   // VPN 身份地址
    uint256 planId,            // 套餐 ID (1=月付, 2=年付, 3=测试)
    uint256 maxAmount,         // USDC 授权上限
    uint256 permitDeadline,    // Permit 截止时间
    uint256 intentNonce,       // 防重放 nonce
    bytes calldata intentSig,  // EIP-712 订阅意图签名
    uint8 permitV,             // EIP-2612 Permit 签名 v
    bytes32 permitR,           // EIP-2612 Permit 签名 r
    bytes32 permitS            // EIP-2612 Permit 签名 s
) external
```

**参数说明**:
- `user`: 付款钱包地址（MetaMask 连接的地址）
- `identityAddress`: VPN 身份地址（用于 VPN 准入的唯一标识）
- `planId`: 套餐 ID
  - `1`: 月付套餐 (5 USDC / 30 天)
  - `2`: 年付套餐 (50 USDC / 365 天)
  - `3`: 测试套餐 (0.1 USDC / 30 分钟) ⚠️ 仅测试网
- `maxAmount`: 用户授权的 USDC 最大金额（6 decimals）
- `permitDeadline`: EIP-2612 Permit 的截止时间戳
- `intentNonce`: 防重放攻击的 nonce（从 `intentNonces[user]` 获取）
- `intentSig`: 用户对 SubscribeIntent 的 EIP-712 签名
- `permitV`, `permitR`, `permitS`: EIP-2612 Permit 签名的三个部分

**V2 变化**:
- ✅ 检查 `identityAddress` 是否已有订阅（而不是检查 `user`）
- ✅ 支持一个钱包为多个 VPN 身份订阅

**调用者**: Relayer (CDP Smart Account)

**Gas**: 由 CDP Paymaster 赞助（0 ETH）

---

### 2. `executeRenewal` - 续费函数

**函数签名**:
```solidity
executeRenewal(address)
```

**完整声明**:
```solidity
function executeRenewal(
    address identityAddress    // VPN 身份地址
) external
```

**参数说明**:
- `identityAddress`: VPN 身份地址（✅ V2 修改：V1 是 `user`，V2 改为 `identityAddress`）

**V2 变化**:
- ✅ 参数从 `user`（付款钱包）改为 `identityAddress`（VPN 身份）
- ✅ 从订阅记录中获取 `payerAddress` 进行扣款
- ✅ 支持为多个 VPN 身份分别续费

**调用者**: Relayer (CDP Smart Account)

**Gas**: 由 CDP Paymaster 赞助（0 ETH）

**触发条件**:
- 订阅已到期（`block.timestamp >= expiresAt`）
- 自动续费已启用（`autoRenewEnabled == true`）
- 付款钱包有足够的 USDC 余额和授权额度

---

### 3. `cancelFor` - 取消订阅函数

**函数签名**:
```solidity
cancelFor(address,address,uint256,bytes)
```

**完整声明**:
```solidity
function cancelFor(
    address user,              // 付款钱包地址
    address identityAddress,   // VPN 身份地址
    uint256 nonce,             // 防重放 nonce
    bytes calldata sig         // EIP-712 取消意图签名
) external
```

**参数说明**:
- `user`: 付款钱包地址
- `identityAddress`: VPN 身份地址（✅ V2 新增参数）
- `nonce`: 防重放攻击的 nonce（从 `cancelNonces[user]` 获取）
- `sig`: 用户对 CancelIntent 的 EIP-712 签名

**V2 变化**:
- ✅ 新增 `identityAddress` 参数
- ✅ 支持取消指定 VPN 身份的订阅（而不是取消用户的唯一订阅）
- ✅ 验证 `payerAddress == user` 确保只有付款钱包可以取消

**调用者**: Relayer (CDP Smart Account)

**Gas**: 由 CDP Paymaster 赞助（0 ETH）

**效果**:
- 关闭自动续费（`autoRenewEnabled = false`）
- 订阅在当前周期结束后自然到期

---

### 4. `finalizeExpired` - 终态清理函数

**函数签名**:
```solidity
finalizeExpired(address,bool)
```

**完整声明**:
```solidity
function finalizeExpired(
    address identityAddress,   // VPN 身份地址
    bool forceClosed           // 是否强制停服
) external
```

**参数说明**:
- `identityAddress`: VPN 身份地址（✅ V2 修改：V1 是 `user`，V2 改为 `identityAddress`）
- `forceClosed`: 是否强制停服
  - `true`: 强制停服（自动续费失败次数超限）
  - `false`: 自然到期（用户已取消自动续费）

**V2 变化**:
- ✅ 参数从 `user`（付款钱包）改为 `identityAddress`（VPN 身份）
- ✅ 从 `userIdentities` 列表中移除该身份
- ✅ 支持清理指定 VPN 身份的订阅

**调用者**: Relayer (CDP Smart Account)

**Gas**: 由 CDP Paymaster 赞助（0 ETH）

**效果**:
- 标记订阅为未激活（`isActive = false`）
- 释放 VPN 身份绑定（`identityToOwner[identityAddress] = address(0)`）
- 从用户的身份列表中移除

---

## 查询函数（只读，不需要 Paymaster）

### `getUserIdentities` - 查询用户的所有订阅身份

```solidity
function getUserIdentities(address user) external view returns (address[] memory)
```

**参数**:
- `user`: 付款钱包地址

**返回**:
- `address[]`: 用户订阅的所有 VPN 身份地址列表

---

### `getUserActiveSubscriptions` - 查询用户的所有活跃订阅

```solidity
function getUserActiveSubscriptions(address user) external view returns (Subscription[] memory)
```

**参数**:
- `user`: 付款钱包地址

**返回**:
- `Subscription[]`: 用户的所有活跃订阅详情

---

### `subscriptions` - 查询单个订阅

```solidity
function subscriptions(address identityAddress) public view returns (Subscription memory)
```

**参数**:
- `identityAddress`: VPN 身份地址（✅ V2 修改：V1 是 `user`，V2 改为 `identityAddress`）

**返回**:
- `Subscription`: 订阅详情
  - `identityAddress`: VPN 身份地址
  - `payerAddress`: 付款钱包地址（✅ V2 新增）
  - `lockedPrice`: 锁定价格
  - `planId`: 套餐 ID
  - `lockedPeriod`: 锁定周期
  - `startTime`: 开始时间
  - `expiresAt`: 到期时间
  - `autoRenewEnabled`: 自动续费开关
  - `isActive`: 是否活跃

---

### `identityToOwner` - 查询 VPN 身份的绑定关系

```solidity
function identityToOwner(address identityAddress) public view returns (address)
```

**参数**:
- `identityAddress`: VPN 身份地址

**返回**:
- `address`: 绑定的付款钱包地址（如果未绑定则返回 `address(0)`）

---

### `plans` - 查询套餐信息

```solidity
function plans(uint256 planId) public view returns (Plan memory)
```

**参数**:
- `planId`: 套餐 ID

**返回**:
- `Plan`: 套餐详情
  - `price`: 价格（USDC, 6 decimals）
  - `period`: 周期（秒）
  - `isActive`: 是否激活

---

## V1 vs V2 核心变化总结

| 函数 | V1 参数 | V2 参数 | 变化说明 |
|------|---------|---------|----------|
| `permitAndSubscribe` | `user, identityAddress, ...` | `user, identityAddress, ...` | ✅ 检查逻辑改为检查 `identityAddress` 而非 `user` |
| `executeRenewal` | `address user` | `address identityAddress` | ✅ 参数改为 VPN 身份地址 |
| `cancelFor` | `address user, uint256 nonce, bytes sig` | `address user, address identityAddress, uint256 nonce, bytes sig` | ✅ 新增 `identityAddress` 参数 |
| `finalizeExpired` | `address user, bool forceClosed` | `address identityAddress, bool forceClosed` | ✅ 参数改为 VPN 身份地址 |
| `subscriptions` mapping | `mapping(address => Subscription)` | `mapping(address => Subscription)` | ✅ key 从 `user` 改为 `identityAddress` |
| `Subscription` struct | 无 `payerAddress` | 有 `payerAddress` | ✅ 新增付款钱包地址字段 |

---

## 使用示例

### 后端 API 调用示例

```javascript
// 查询用户的所有订阅
const identities = await contract.getUserIdentities(userAddress);
console.log('用户订阅的 VPN 身份:', identities);

// 查询单个 VPN 身份的订阅详情
const subscription = await contract.subscriptions(identityAddress);
console.log('订阅详情:', {
  payerAddress: subscription.payerAddress,
  expiresAt: subscription.expiresAt,
  isActive: subscription.isActive
});

// 自动续费：遍历用户的所有订阅
for (const identity of identities) {
  const sub = await contract.subscriptions(identity);
  if (sub.isActive && sub.autoRenewEnabled && isExpired(sub.expiresAt)) {
    await executeRenewal(identity); // 传递 identityAddress 而非 user
  }
}
```

---

## 注意事项

1. **V2 核心变化**：订阅索引从 `付款钱包 → 订阅` 改为 `VPN 身份 → 订阅`
2. **多订阅支持**：一个钱包可以为多个 VPN 身份订阅服务
3. **身份唯一性**：一个 VPN 身份只能有一个活跃订阅
4. **Gas 赞助**：所有写入函数由 CDP Paymaster 赞助 gas（0 ETH）
5. **测试套餐**：Plan 3 (0.1 USDC / 30 分钟) 仅用于测试网，主网部署时应移除

---

## 相关文档

- [重构方案](../SUBSCRIPTION_REDESIGN.md)
- [部署状态](DEPLOYMENT_STATUS.md)
- [V2 合约源码](src/VPNSubscriptionV2.sol)
- [部署脚本](script/DeployV2.s.sol)

---

**最后更新**: 2026-04-13
**合约版本**: V2
**合约地址**: 0x16D6D1564942798720CB69a6814bc2C53ECe23a1 (Base Sepolia)
