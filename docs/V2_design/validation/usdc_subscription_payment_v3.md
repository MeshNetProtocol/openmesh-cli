# VPN 订阅支付技术方案 V3.3 — CDP Paymaster + Permit + Server Wallet

**创建日期**: 2026-04-10
**基于**: V3.2 评审意见修订（2026-04-10，评审人：Codex）
**核心变化**（相对 V3.2）:
- 签名格式统一为 EIP-712 typed data：`SubscribeIntent` 和 `cancelFor` 合约验签与前端签名格式对齐，解决 V3.2 中 `recover` 地址不匹配的根本问题
- 补齐取消后自然到期的链上终态路径：新增 `finalizeExpired(user)` 函数，释放 `isActive` 和 `identityToOwner`，允许用户重新订阅
- 统一续费逻辑：废弃"提前 24h 链上续费"的矛盾说法，改为"到期前 24h 预检和提醒，到期后才发起链上续费"；失败计数统一在后端 DB 维护，合约移除 `renewalFailCount`
- `permitAmount` 计算改为 planId 显式映射，不依赖 period 区间判断
- 补充 `lockedPrice` 截断保护：`setPlan` 和 `permitAndSubscribe` 显式校验 `price <= type(uint96).max`，避免管理员误配导致快照价格截断
- 收紧 failCount 语义：到期前 24h 预检仅做提醒，不重复累计失败次数；`failCount` 仅在到期后续费失败时增加，避免预检窗口内被快速打满

---

## 一、为什么升级到 V3：CDP 能力澄清

### 1.1 V2 方案的遗留问题

V2（Permit + 自建 Relayer）方案中，后端需要：
- 自持一个 ETH 钱包作为 Relayer
- 维护该钱包的 ETH 余额（gas 储备）
- 自建 nonce 管理、重试逻辑、私钥安全存储

这些都是**不必要的基础设施负担**，CDP 已经有成熟的方案可以替代。

### 1.2 为什么去掉 EIP-7702

本方案的执行路径是：

```
用户 EOA（只做链下签名）→ 后端 → CDP Server Wallet（ERC-4337，实际发单方）→ Paymaster 赞助
```

CDP Server Wallet 本身已是 ERC-4337 智能合约钱包，可以直接使用 Paymaster，不需要用户 EOA 做任何升级。

**本方案明确定位为**：`permit + CDP Server Wallet + CDP Paymaster` 的托管 Relayer 方案。

### 1.3 CDP 的相关能力（已核实）

| 能力 | 产品 | 说明 |
|---|---|---|
| **Gas 赞助** | CDP Paymaster | 托管式 Paymaster + Bundler 一体；CDP 代付 gas，月度账单收取 **gas 费 + 7% 服务费** |
| **后端托管钱包** | CDP Server Wallets | 全托管的智能合约钱包（ERC-4337），无需管理私钥，通过 API 发起交易；CDP 负责签名、nonce、重试 |
| **免费额度** | Base Gasless Campaign | 申请最高 $15,000 gas credits |

---

## 二、最终架构

### 2.1 整体分层

```
┌───────────────────────────────────────────────────────────┐
│                用户侧（普通 MetaMask，零 gas）              │
│                                                           │
│   Web 订阅页面                                            │
│     │                                                     │
│     ├─ 首次订阅：签名 SubscribeIntent（EIP-712）+ permit   │
│     │  （两个链下签名，均不花 gas）                         │
│     │  SubscribeIntent：绑定 identityAddress/planId/maxAmount│
│     │  permit：链上 USDC 授权额度                          │
│     │                                                     │
│     └─ 取消订阅：签名 CancelIntent（EIP-712，零 gas）      │
│        关闭 autoRenewEnabled，服务持续至 expiresAt         │
└─────────────────────┬─────────────────────────────────────┘
                      │ HTTPS（签名数据）
                      ▼
┌───────────────────────────────────────────────────────────┐
│                 后端服务（Go）                             │
│                                                           │
│  Subscription API                                         │
│       │                                                   │
│       ├─ 幂等锁（IdempotencyKey + intentNonce 双层）       │
│       ├─ SubscribeIntent / CancelIntent 签名验证          │
│       ├─ identityAddress 唯一性校验（DB 层）               │
│       │                                                   │
│  CDP Server Wallet（托管智能合约钱包，唯一发单方）          │
│       │                                                   │
│  定时任务                                                  │
│  ├─ 到期前 24h：预检资金 + 发送提醒（不发链上交易）        │
│  ├─ 到期后：发起链上 executeRenewal                       │
│  ├─ 后端 failCount >= 3：发起链上 finalizeExpired 停服     │
│  └─ 自然到期（cancel 后）：发起链上 finalizeExpired 收口   │
└──────────────────────┬──────────────────────┬─────────────┘
                       │ UserOperation         │ Gas 赞助请求
                       ▼                       ▼
┌──────────────────────────────────────────────────────────┐
│              CDP 基础设施（托管）                          │
│              Bundler ←→ Paymaster                         │
│              策略：合约白名单 + 全局月度上限               │
└───────────────────────────────┬──────────────────────────┘
                                │ 链上交易
                                ▼
┌───────────────────────────────────────────────────────────┐
│  Base Mainnet                                             │
│  USDC 合约（ERC-2612 permit 支持）                        │
│  VPNSubscription 合约                                     │
└───────────────────────────────────────────────────────────┘
```

### 2.2 关键角色重新定义

| 角色 | V2 方案 | V3.3 方案 |
|---|---|---|
| Gas 付款方 | 自持 ETH 钱包（手动维护） | CDP Paymaster（托管，月度账单） |
| 交易发起方 | 自建 Relayer（私钥自管） | CDP Server Wallet（CDP 托管私钥） |
| 业务参数防篡改 | 无 | SubscribeIntent EIP-712 签名 |
| 续费失败计数 | — | 后端 DB 维护，不依赖链上状态 |
| 终态清理 | — | 后端调用 `finalizeExpired` |
| 费用 | 需预充 ETH | gas + 7%，无需预充，月度发票 |

---

## 三、数据流

### 3.1 首次订阅（用户零 gas）

```
① 用户连接 MetaMask，选择套餐

② 前端请求两个链下签名（均不花 gas）：

   签名 1：SubscribeIntent（EIP-712 typed data）
   domain:  { name: "VPNSubscription", version: "1", chainId, verifyingContract: CONTRACT }
   types:   SubscribeIntent { address user, address identityAddress, uint256 planId,
                              uint256 maxAmount, uint256 deadline, uint256 nonce }

   签名 2：ERC-2612 permit
   maxAmount 按套餐 planId 映射（见 5.2 节）

③ 前端 POST /api/subscribe（所有签名数据 + IdempotencyKey）

④ 后端：
   - IdempotencyKey 幂等校验
   - 离链验证 SubscribeIntent 签名（防无效请求占用链上资源）
   - identityAddress 未被其他 userAddress 占用（DB 唯一索引）
   - intentNonce 未被消费

⑤ 后端通过 CDP Server Wallet API 发送交易：
   permitAndSubscribe(user, identityAddress, planId, maxAmount, deadline, intentNonce, intentSig, permitV/R/S)

⑥ CDP Paymaster 赞助 gas → 交易上链

⑦ 合约执行：
   EIP-712 验证 intentSig → permit → transferFrom →
   记录订阅（快照 lockedPrice / lockedPeriod）

⑧ 后端监听 SubscriptionCreated 事件 → Xray 添加用户，激活 VPN
```

### 3.2 自动续费（用户无感知）

```
续费时机策略（合约要求 block.timestamp >= expiresAt 才能续费，策略与此对齐）：

  阶段一：到期前 24h（预检和提醒，不发链上交易）
    - 定时任务检查 expiresAt ≤ now + 24h 的 autoRenewEnabled=true 订阅
    - 预检链上 allowance / balance（view call，免费）
    - 不足 → 记录预警状态并通知用户（同一账期去重，不累计 failCount）
    - 充足 → 无需操作，等待到期

  阶段二：到期后（发起链上续费）
    - 定时任务检查 expiresAt ≤ now 的 autoRenewEnabled=true 订阅
    - 幂等锁：userAddress + expiresAt 不重复
    - 再次预检资金；不足 → DB failCount++，通知用户
    - 充足 → CDP Server Wallet 调用 executeRenewal(user)
    - 合约扣款成功 → expiresAt += lockedPeriod，DB 更新

  failCount >= MAX_RENEWAL_FAILS（3）：
    - 后端 DB 标记停服，Xray 删除用户
    - 后端调用 finalizeExpired(user)：链上 isActive=false，释放 identityToOwner
    - 发出 SubscriptionForceClosed 事件

  注：MAX_RENEWAL_FAILS 计数在后端 DB 维护，不依赖链上状态。
     合约中已移除 renewalFailCount，逻辑更简洁可控。
```

### 3.3 取消订阅（用户零 gas，关闭自动续费）

```
语义：取消 = 关闭 autoRenewEnabled，服务持续至 expiresAt，期满后由后端调用
      finalizeExpired(user) 清理链上状态，允许重新订阅。

① 用户签名 CancelIntent（EIP-712 typed data，零 gas）
   domain:  { name: "VPNSubscription", version: "1", chainId, verifyingContract: CONTRACT }
   types:   CancelIntent { address user, uint256 nonce }

② 前端 POST /api/cancel

③ 后端验证签名，通过 CDP Server Wallet 调用：
   cancelFor(user, nonce, sig)

④ 合约：EIP-712 验证签名 → cancelNonces[user]++ → autoRenewEnabled = false
   （isActive 不变，服务继续至 expiresAt）

⑤ 后端更新 DB：autoRenewEnabled = false
   定时续费任务跳过该订阅

⑥ expiresAt 到达后（DB 层判定）：
   - Xray 删除用户（停服）
   - 后端调用 finalizeExpired(user)：isActive=false，释放 identityToOwner
   - 用户此后可重新发起订阅

说明：finalizeExpired 的目的是释放链上状态，让用户能重新订阅。
      Xray 停服以 DB 层 expiresAt 判定为准，不要求链上可证明。
```

### 3.4 订阅状态机

```
                    ┌──────────┐
                    │ pending  │ （支付提交，等待上链）
                    └────┬─────┘
                         │ SubscriptionCreated 事件
                         ▼
                    ┌──────────┐
              ┌────►│  active  │◄────────────────────┐
              │     └────┬─────┘                     │
              │          │ expiresAt - 24h            │
              │          ▼                            │
              │     ┌──────────┐                      │ executeRenewal 成功
              │     │ expiring │                      │
              │     └────┬─────┘                     │
              │          │ expiresAt 到达             │
              │          ▼                            │
              │     执行链上续费 ──────────────────────┘
              │          │ 续费失败 (failCount++)
              │          ▼
              │     failCount >= 3？
              │       是 → 后端停服 + finalizeExpired → ┐
              │       否 → 继续等待下次尝试             │
              │                                        │
              │ 用户取消 (cancelFor)                   │
              │     ▼                                  │
              │ ┌──────────┐                           │
              │ │cancelled │ (autoRenewEnabled=false,  │
              │ │          │  isActive=true，服务继续) │
              │ └────┬─────┘                           │
              │      │ expiresAt 到达                  │
              │      │ 后端停服 + finalizeExpired       │
              │      ▼                                  │
              │ ┌──────────┐                           │
              └─│  closed  │◄──────────────────────────┘
                └──────────┘ (isActive=false，可重新订阅)
```

---

## 四、智能合约

### 4.1 主要变化（相对 V3.2）

1. **签名格式统一为 EIP-712**：`SubscribeIntent` 和 `CancelIntent` 均使用 `_hashTypedDataV4`，与前端 `signTypedData` 完全对称
2. **移除链上 `renewalFailCount`**：失败计数移至后端 DB，合约不再维护
3. **新增 `finalizeExpired(user)`**：`onlyRelayer` 可调，在自然到期或强制停服后清理链上状态
4. **移除 `SubscriptionAutoSuspended` 事件**：由后端在调用 `finalizeExpired` 前完成停服，通过 `SubscriptionForceClosed` 事件通知
5. **增加 `uint96` 安全校验**：`plan.price` 在写入 `lockedPrice` 前显式校验，避免截断

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract VPNSubscription is Ownable, Pausable, ReentrancyGuard, EIP712 {

    using ECDSA for bytes32;

    // ─── EIP-712 type hashes ───────────────────────────────────────────
    bytes32 private constant SUBSCRIBE_INTENT_TYPEHASH = keccak256(
        "SubscribeIntent(address user,address identityAddress,uint256 planId,uint256 maxAmount,uint256 deadline,uint256 nonce)"
    );
    bytes32 private constant CANCEL_INTENT_TYPEHASH = keccak256(
        "CancelIntent(address user,uint256 nonce)"
    );

    // ─── 常量 ──────────────────────────────────────────────────────────
    IERC20Permit public immutable usdc;
    uint256 public constant USDC_UNIT = 1e6;

    // ─── 可配置 ────────────────────────────────────────────────────────
    address public serviceWallet;
    address public relayer;

    // ─── 套餐 ──────────────────────────────────────────────────────────
    struct Plan {
        uint256 price;
        uint256 period;
        bool    isActive;
    }
    mapping(uint256 => Plan) public plans;

    // ─── 订阅（内存布局优化：identityAddress + lockedPrice 共 slot 0）──
    struct Subscription {
        address identityAddress;   // slot 0: 20 bytes
        uint96  lockedPrice;       // slot 0: 12 bytes（USDC max supply < 2^96）
        uint256 planId;            // slot 1
        uint256 lockedPeriod;      // slot 2
        uint256 startTime;         // slot 3
        uint256 expiresAt;         // slot 4
        bool    autoRenewEnabled;  // slot 5
        bool    isActive;          // slot 5
    }
    mapping(address => Subscription) public subscriptions;

    // ─── identity 唯一性 ───────────────────────────────────────────────
    // 防止同一 VPN 身份被多个付款地址绑定
    mapping(address => address) public identityToOwner;

    // ─── 防重放 nonce ──────────────────────────────────────────────────
    mapping(address => uint256) public intentNonces; // SubscribeIntent
    mapping(address => uint256) public cancelNonces; // CancelIntent

    // ─── 事件 ──────────────────────────────────────────────────────────
    event SubscriptionCreated(
        address indexed user,
        address indexed identity,
        uint256 planId,
        uint96  lockedPrice,
        uint256 lockedPeriod,
        uint256 expiresAt
    );
    event SubscriptionRenewed(address indexed user, uint256 newExpiresAt);
    event SubscriptionCancelled(address indexed user);        // autoRenewEnabled = false
    event SubscriptionForceClosed(address indexed user);      // finalizeExpired 强制停服
    event SubscriptionExpired(address indexed user);          // finalizeExpired 自然到期
    event RenewalFailed(address indexed user, string reason); // 链上扣款失败

    modifier onlyRelayer() {
        require(msg.sender == relayer, "VPN: not relayer");
        _;
    }

    constructor(
        address _usdc,
        address _serviceWallet,
        address _relayer
    ) Ownable(msg.sender) EIP712("VPNSubscription", "1") {
        usdc = IERC20Permit(_usdc);
        serviceWallet = _serviceWallet;
        relayer = _relayer;
        plans[1] = Plan({ price: 5  * USDC_UNIT, period: 30 days,  isActive: true });
        plans[2] = Plan({ price: 50 * USDC_UNIT, period: 365 days, isActive: true });
    }

    // ─────────────────────────────────────────
    // 订阅
    // ─────────────────────────────────────────

    /// @notice 首次订阅
    /// @param user             付款地址
    /// @param identityAddress  VPN 准入身份（链上唯一性校验）
    /// @param planId           套餐 ID
    /// @param maxAmount        用户确认的 permit 授权上限（== permit value）
    /// @param permitDeadline   permit 截止时间（== SubscribeIntent deadline）
    /// @param intentNonce      SubscribeIntent 防重放 nonce（== intentNonces[user]）
    /// @param intentSig        用户对 SubscribeIntent 的 EIP-712 签名
    /// @param permitV/R/S      ERC-2612 permit 签名
    function permitAndSubscribe(
        address user,
        address identityAddress,
        uint256 planId,
        uint256 maxAmount,
        uint256 permitDeadline,
        uint256 intentNonce,
        bytes calldata intentSig,
        uint8 permitV, bytes32 permitR, bytes32 permitS
    ) external onlyRelayer whenNotPaused nonReentrant {

        require(identityAddress != address(0),              "VPN: invalid identity");
        require(permitDeadline >= block.timestamp,          "VPN: permit expired");

        Plan memory plan = plans[planId];
        require(plan.isActive,                              "VPN: plan not available");
        require(!subscriptions[user].isActive,              "VPN: already subscribed");
        require(maxAmount >= plan.price,                    "VPN: maxAmount too low");
        require(plan.price <= type(uint96).max,             "VPN: price overflow");
        require(identityToOwner[identityAddress] == address(0), "VPN: identity already bound");

        // ── EIP-712 SubscribeIntent 验签 ──
        require(intentNonce == intentNonces[user],          "VPN: invalid intent nonce");
        bytes32 structHash = keccak256(abi.encode(
            SUBSCRIBE_INTENT_TYPEHASH,
            user,
            identityAddress,
            planId,
            maxAmount,
            permitDeadline,
            intentNonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(intentSig);
        require(signer == user,                             "VPN: invalid intent signature");
        intentNonces[user]++;

        // ── ERC-2612 permit ──
        usdc.permit(user, address(this), maxAmount, permitDeadline, permitV, permitR, permitS);

        // ── 扣款 ──
        require(
            IERC20(address(usdc)).transferFrom(user, serviceWallet, plan.price),
            "VPN: transfer failed"
        );

        // ── 写入订阅（快照成交时套餐参数） ──
        identityToOwner[identityAddress] = user;
        subscriptions[user] = Subscription({
            identityAddress:  identityAddress,
            lockedPrice:      uint96(plan.price),
            planId:           planId,
            lockedPeriod:     plan.period,
            startTime:        block.timestamp,
            expiresAt:        block.timestamp + plan.period,
            autoRenewEnabled: true,
            isActive:         true
        });

        emit SubscriptionCreated(
            user, identityAddress, planId,
            uint96(plan.price), plan.period,
            block.timestamp + plan.period
        );
    }

    // ─────────────────────────────────────────
    // 链上续费
    // ─────────────────────────────────────────

    /// @notice 到期后由 Relayer 发起续费
    /// 失败计数在后端 DB 维护，合约只负责执行或 emit 失败事件
    function executeRenewal(address user) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[user];
        require(sub.isActive,                               "VPN: not subscribed");
        require(sub.autoRenewEnabled,                       "VPN: auto renew disabled");
        require(block.timestamp >= sub.expiresAt,           "VPN: not yet expired");

        uint256 price  = uint256(sub.lockedPrice);
        uint256 period = sub.lockedPeriod;

        uint256 allowance = IERC20(address(usdc)).allowance(user, address(this));
        uint256 balance   = IERC20(address(usdc)).balanceOf(user);

        if (allowance < price) { emit RenewalFailed(user, "insufficient allowance"); return; }
        if (balance   < price) { emit RenewalFailed(user, "insufficient balance");   return; }

        require(
            IERC20(address(usdc)).transferFrom(user, serviceWallet, price),
            "VPN: transfer failed"
        );
        sub.expiresAt = sub.expiresAt + period;

        emit SubscriptionRenewed(user, sub.expiresAt);
    }

    // ─────────────────────────────────────────
    // 取消订阅（关闭自动续费）
    // ─────────────────────────────────────────

    /// @notice 用户亲自上链取消（需 gas）
    function cancelSubscription() external {
        Subscription storage sub = subscriptions[msg.sender];
        require(sub.isActive,           "VPN: not subscribed");
        require(sub.autoRenewEnabled,   "VPN: already cancelled");
        sub.autoRenewEnabled = false;
        emit SubscriptionCancelled(msg.sender);
    }

    /// @notice Relayer 代发取消（用户零 gas），使用 EIP-712 CancelIntent
    function cancelFor(
        address user,
        uint256 nonce,
        bytes calldata sig
    ) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[user];
        require(sub.isActive,           "VPN: not subscribed");
        require(sub.autoRenewEnabled,   "VPN: already cancelled");
        require(nonce == cancelNonces[user], "VPN: invalid nonce");

        // ── EIP-712 CancelIntent 验签 ──
        bytes32 structHash = keccak256(abi.encode(
            CANCEL_INTENT_TYPEHASH,
            user,
            nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(sig);
        require(signer == user,         "VPN: invalid signature");

        cancelNonces[user]++;
        sub.autoRenewEnabled = false;
        emit SubscriptionCancelled(user);
    }

    // ─────────────────────────────────────────
    // 终态清理
    // ─────────────────────────────────────────

    /// @notice 清理已到期的订阅，释放链上状态，允许用户重新订阅
    /// 适用于两类场景：
    ///   1. 自然到期：用户已 cancel（autoRenewEnabled=false），当前周期结束
    ///   2. 强制停服：后端 failCount >= MAX_RENEWAL_FAILS，决定停服
    /// @param user         订阅用户地址
    /// @param forceClosed  true = 强制停服（failCount 超限），false = 自然到期
    function finalizeExpired(address user, bool forceClosed)
        external onlyRelayer whenNotPaused nonReentrant
    {
        Subscription storage sub = subscriptions[user];
        require(sub.isActive,                               "VPN: not active");

        if (!forceClosed) {
            // 自然到期：必须已关闭自动续费且已过期
            require(!sub.autoRenewEnabled,                  "VPN: auto renew still on");
            require(block.timestamp >= sub.expiresAt,       "VPN: not yet expired");
        }
        // forceClosed 场景：后端已做停服决定，不限制 autoRenewEnabled 状态

        address identity = sub.identityAddress;
        sub.isActive = false;
        sub.autoRenewEnabled = false;
        identityToOwner[identity] = address(0); // 释放 identity 绑定，允许重新使用

        if (forceClosed) {
            emit SubscriptionForceClosed(user);
        } else {
            emit SubscriptionExpired(user);
        }
    }

    // ─────────────────────────────────────────
    // Owner 管理
    // ─────────────────────────────────────────

    // 注意：改价只影响新订阅，已有订阅续费按 lockedPrice/lockedPeriod 执行
    function setPlan(uint256 id, uint256 price, uint256 period, bool active) external onlyOwner {
        require(price <= type(uint96).max, "VPN: price too large");
        plans[id] = Plan(price, period, active);
    }
    function setRelayer(address r) external onlyOwner { relayer = r; }
    function setServiceWallet(address w) external onlyOwner { serviceWallet = w; }
    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
```

> **部署说明**：部署时 `_relayer` 参数填写 CDP Server Wallet 创建后的地址。后续可通过 `setRelayer()` 更换，无需重新部署合约。

---

## 五、前端集成

### 5.1 依赖

```bash
npm install viem @coinbase/wallet-sdk
```

### 5.2 订阅流程（SubscribeIntent EIP-712 + permit 双签名）

```typescript
import { createWalletClient, custom } from 'viem';
import { base } from 'viem/chains';

const USDC_ADDRESS     = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const CONTRACT_ADDRESS = '0x...';

// permitAmount 按 planId 显式映射，不依赖 period 区间判断
// key: planId, value: 授权期数
const PERMIT_PERIODS: Record<number, bigint> = {
  1: 12n,  // 月付（30d）：授权 12 个月
  2: 2n,   // 年付（365d）：授权 2 个周期
  // 新增套餐在此处明确配置，不使用默认值
};

// EIP-712 domain（与合约构造器 EIP712("VPNSubscription", "1") 一致）
const SUBSCRIBE_INTENT_DOMAIN = {
  name:              'VPNSubscription',
  version:           '1',
  chainId:           base.id,
  verifyingContract: CONTRACT_ADDRESS,
} as const;

const SUBSCRIBE_INTENT_TYPES = {
  SubscribeIntent: [
    { name: 'user',            type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'planId',          type: 'uint256' },
    { name: 'maxAmount',       type: 'uint256' },
    { name: 'deadline',        type: 'uint256' },
    { name: 'nonce',           type: 'uint256' },
  ],
} as const;

async function subscribe(planId: number) {
  const walletClient = createWalletClient({ chain: base, transport: custom(window.ethereum) });
  const [userAddress] = await walletClient.requestAddresses();

  const planInfo = await fetchPlanInfo(planId); // { price: bigint, period: number }

  // 余额预检
  const balance = await readUsdcBalance(userAddress);
  if (balance < planInfo.price) {
    throw new Error(`USDC 余额不足。需要 ${planInfo.price}，当前 ${balance}`);
  }

  const periods = PERMIT_PERIODS[planId];
  if (!periods) throw new Error(`未配置套餐 ${planId} 的授权期数`);
  const maxAmount = planInfo.price * periods;

  const deadline        = BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 3600);
  const permitNonce     = await readUsdcNonce(userAddress);
  const identityAddress = await getIdentityAddress();

  const { nonce: intentNonce } = await fetch(
    `/api/intent-nonce?address=${userAddress}`
  ).then(r => r.json());

  const idempotencyKey = crypto.randomUUID();

  // ── 签名 1：SubscribeIntent（EIP-712 typed data，与合约验签完全对称）──
  const intentSig = await walletClient.signTypedData({
    account:     userAddress,
    domain:      SUBSCRIBE_INTENT_DOMAIN,
    types:       SUBSCRIBE_INTENT_TYPES,
    primaryType: 'SubscribeIntent',
    message: {
      user:            userAddress,
      identityAddress: identityAddress,
      planId:          BigInt(planId),
      maxAmount,
      deadline,
      nonce:           BigInt(intentNonce),
    },
  });

  // ── 签名 2：ERC-2612 permit ──
  const permitSig = await walletClient.signTypedData({
    account:     userAddress,
    domain:      { name: 'USD Coin', version: '2', chainId: base.id, verifyingContract: USDC_ADDRESS },
    types: {
      Permit: [
        { name: 'owner',    type: 'address' },
        { name: 'spender',  type: 'address' },
        { name: 'value',    type: 'uint256' },
        { name: 'nonce',    type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    },
    primaryType: 'Permit',
    message: {
      owner:    userAddress,
      spender:  CONTRACT_ADDRESS,
      value:    maxAmount,
      nonce:    permitNonce,
      deadline,
    },
  });

  return fetch('/api/subscribe', {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      userAddress,
      identityAddress,
      planId,
      maxAmount:      maxAmount.toString(),
      permitDeadline: deadline.toString(),
      intentNonce,
      intentSig,
      permitSig,
      idempotencyKey,
    }),
  }).then(r => r.json());
}
```

### 5.3 取消订阅流程（CancelIntent EIP-712，零 gas）

```typescript
const CANCEL_INTENT_DOMAIN = SUBSCRIBE_INTENT_DOMAIN; // 同一合约，同一 domain

const CANCEL_INTENT_TYPES = {
  CancelIntent: [
    { name: 'user',  type: 'address' },
    { name: 'nonce', type: 'uint256' },
  ],
} as const;

async function cancelSubscription() {
  const walletClient = createWalletClient({ chain: base, transport: custom(window.ethereum) });
  const [userAddress] = await walletClient.requestAddresses();

  const { nonce } = await fetch(
    `/api/cancel-nonce?address=${userAddress}`
  ).then(r => r.json());

  // EIP-712 CancelIntent（与合约 cancelFor 验签完全对称）
  const sig = await walletClient.signTypedData({
    account:     userAddress,
    domain:      CANCEL_INTENT_DOMAIN,
    types:       CANCEL_INTENT_TYPES,
    primaryType: 'CancelIntent',
    message: {
      user:  userAddress,
      nonce: BigInt(nonce),
    },
  });

  return fetch('/api/cancel', {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userAddress, nonce, sig }),
  }).then(r => r.json());
  // 取消后服务继续至 expiresAt，不立即停服
}
```

### 5.4 错误处理

```typescript
const ERROR_MESSAGES: Record<string, string> = {
  'user rejected':            '您取消了签名，操作未执行',
  'insufficient allowance':   'USDC 授权额度不足，请重新签名',
  'insufficient balance':     'USDC 余额不足，请充值后重试',
  'already subscribed':       '您已有活跃订阅，无需重复订阅',
  'plan not available':       '该套餐暂不可用，请选择其他套餐',
  'identity already bound':   '该 VPN 身份已被其他地址绑定',
  'invalid intent signature': '签名验证失败，请重试',
  'already cancelled':        '订阅已取消自动续费',
};
```

---

## 六、后端集成（CDP SDK）

### 6.1 初始化 CDP Server Wallet（一次性）

```go
// 通过 CDP API 创建 Server Wallet（一次性操作）
// CDP 托管私钥，通过 API Key 调用，无需管理私钥或 ETH 余额
// 参考：https://docs.cdp.coinbase.com/wallets/server-wallets
```

### 6.2 订阅 API

```go
func (h *Handler) Subscribe(w http.ResponseWriter, r *http.Request) {
    var req SubscribeRequest
    json.NewDecoder(r.Body).Decode(&req)

    // 双重幂等：IdempotencyKey 防网络重试，intentNonce 防签名重放
    if dup, _ := h.db.CheckIdempotencyKey(r.Context(), req.IdempotencyKey); dup {
        http.Error(w, "duplicate request", 409)
        return
    }

    // 离链验证 SubscribeIntent EIP-712 签名（防无效请求浪费链上资源）
    if !verifySubscribeIntentSig(req) {
        http.Error(w, "invalid intent signature", 400)
        return
    }

    // identityAddress 唯一性（DB 层；链上也有保障，双保险）
    if bound, _ := h.db.IsIdentityBound(r.Context(), req.IdentityAddress); bound {
        http.Error(w, "identity already bound", 409)
        return
    }

    txHash, err := h.cdpWallet.SendTransaction(r.Context(), CDPTxRequest{
        To:   CONTRACT_ADDRESS,
        Data: encodePermitAndSubscribe(req),
    })
    if err != nil {
        http.Error(w, "transaction failed", 500)
        return
    }

    h.db.SaveIdempotencyKey(r.Context(), req.IdempotencyKey, txHash)
    go h.waitAndActivate(txHash, req.UserAddress, req.IdentityAddress)
    json.NewEncoder(w).Encode(map[string]string{"txHash": txHash})
}
```

### 6.3 取消 API

```go
func (h *Handler) Cancel(w http.ResponseWriter, r *http.Request) {
    var req CancelRequest
    json.NewDecoder(r.Body).Decode(&req)

    if !h.rateLimiter.Allow(req.UserAddress) {
        http.Error(w, "rate limited", 429)
        return
    }

    // 离链验证 CancelIntent EIP-712 签名
    if !verifyCancelIntentSig(req) {
        http.Error(w, "invalid signature", 400)
        return
    }

    txHash, err := h.cdpWallet.SendTransaction(r.Context(), CDPTxRequest{
        To:   CONTRACT_ADDRESS,
        Data: encodeCancelFor(req.UserAddress, req.Nonce, req.Sig),
    })
    if err != nil {
        http.Error(w, "transaction failed", 500)
        return
    }

    go h.waitAndMarkCancelled(txHash, req.UserAddress)
    json.NewEncoder(w).Encode(map[string]string{"txHash": txHash})
}
```

### 6.4 定时任务：预检 + 续费 + 停服

```go
// MAX_RENEWAL_FAILS = 3，在后端 DB 维护，合约不感知
const MaxRenewalFails = 3

func (s *RenewalService) tick(ctx context.Context) {
    now := time.Now()

    // ── 阶段一：到期前 24h，预检和提醒（不发链上交易）────────────────
    precheck := s.db.FindSubscriptions(ctx, SubscriptionFilter{
        AutoRenewEnabled: true,
        ExpiresAfter:     now,
        ExpiresBefore:    now.Add(24 * time.Hour),
    })
    for _, sub := range precheck {
        if !s.checkFunds(ctx, sub.UserAddress, sub.LockedPrice) {
            // 预检阶段只做提醒，不累计 failCount，避免 24h 窗口内被重复打满
            s.db.MarkPrecheckInsufficientFunds(ctx, sub.UserAddress, sub.ExpiresAt)
            s.notifier.SendLowBalanceAlertOnce(ctx, sub.UserAddress, sub.ExpiresAt)
        }
    }

    // ── 阶段二：已到期，发起链上续费 ──────────────────────────────────
    expired := s.db.FindSubscriptions(ctx, SubscriptionFilter{
        AutoRenewEnabled: true,
        ExpiresAtOrBefore: now,
    })
    for _, sub := range expired {
        // failCount 超限 → 停服
        if sub.RenewalFailCount >= MaxRenewalFails {
            s.forceClose(ctx, sub)
            continue
        }

        // 幂等锁：userAddress + expiresAt 不重复
        if locked, _ := s.db.AcquireRenewalLock(ctx, sub.UserAddress, sub.ExpiresAt); !locked {
            continue
        }

        // 资金充足再发链上续费
        if !s.checkFunds(ctx, sub.UserAddress, sub.LockedPrice) {
            s.db.IncrRenewalFailCount(ctx, sub.UserAddress)
            s.notifier.SendLowBalanceAlert(sub.UserAddress)
            s.db.ReleaseRenewalLock(ctx, sub.UserAddress, sub.ExpiresAt)
            continue
        }

        txHash, err := s.cdpWallet.SendTransaction(ctx, CDPTxRequest{
            To:   CONTRACT_ADDRESS,
            Data: encodeExecuteRenewal(sub.UserAddress),
        })
        if err != nil {
            s.db.IncrRenewalFailCount(ctx, sub.UserAddress)
            s.db.ReleaseRenewalLock(ctx, sub.UserAddress, sub.ExpiresAt)
            continue
        }
        s.waitAndUpdateDB(ctx, txHash, sub.UserAddress)
    }

    // ── 阶段三：已取消自动续费且自然到期 → finalizeExpired ───────────
    naturalExpired := s.db.FindSubscriptions(ctx, SubscriptionFilter{
        AutoRenewEnabled: false,
        IsActive:         true,
        ExpiresAtOrBefore: now,
    })
    for _, sub := range naturalExpired {
        s.xray.RemoveUser(ctx, sub.IdentityAddress) // 先停服
        txHash, err := s.cdpWallet.SendTransaction(ctx, CDPTxRequest{
            To:   CONTRACT_ADDRESS,
            Data: encodeFinalizeExpired(sub.UserAddress, false), // forceClosed=false
        })
        if err != nil {
            s.logger.Printf("[finalizeExpired:natural] failed for %s: %v", sub.UserAddress, err)
            continue
        }
        s.waitAndMarkExpired(ctx, txHash, sub.UserAddress)
    }
}

// forceClose：failCount 超限时停服并清理链上状态
func (s *RenewalService) forceClose(ctx context.Context, sub Subscription) {
    s.xray.RemoveUser(ctx, sub.IdentityAddress)
    txHash, err := s.cdpWallet.SendTransaction(ctx, CDPTxRequest{
        To:   CONTRACT_ADDRESS,
        Data: encodeFinalizeExpired(sub.UserAddress, true), // forceClosed=true
    })
    if err != nil {
        s.logger.Printf("[finalizeExpired:force] failed for %s: %v", sub.UserAddress, err)
        return
    }
    s.waitAndMarkForceClosed(ctx, txHash, sub.UserAddress)
}
```

### 6.5 链上事件监听与补偿机制

```go
// 事件 → 后端动作：
// SubscriptionCreated    → Xray 添加用户，DB 置 active
// SubscriptionRenewed    → DB 更新 expiresAt，重置 failCount
// SubscriptionCancelled  → DB 置 autoRenewEnabled=false（服务继续）
// RenewalFailed          → DB incrFailCount（仅到期后链上续费失败），通知用户
// SubscriptionExpired    → DB 置 closed（自然到期路径）
// SubscriptionForceClosed → DB 置 closed（强制停服路径）

// 补偿机制（每 6 小时对账）：
// - 链上 isActive=false 但 DB active → 停服并更新 DB
// - 链上 isActive=true 但 DB closed  → 告警人工处理
// - Xray 同步失败 → 自动重试最多 3 次（指数退避）
```

### 6.6 intentNonce / cancelNonce 并发安全

```go
// 查询 nonce 接口需要"预留"语义，防止并发重复 sponsor：
// 方案：查询 nonce 时在 DB 中乐观写入"pending"状态，
//       若该 nonce 的交易在 N 分钟内没有上链，后端释放该记录。
// 实现：intentNonce 以链上 intentNonces[user] 为最终权威，
//       后端 DB 只做"in-flight"记录，不做持久存储。
// 效果：并发请求中最多一个能通过链上 intentNonce 校验，其余 revert。
```

---

## 七、CDP Paymaster 配置

```
合约白名单：
  - 仅赞助对 VPNSubscription 合约的调用
  - 允许方法：permitAndSubscribe, executeRenewal, cancelFor, finalizeExpired

支出控制：
  - 全局月度上限：$50（根据用户规模调整）
  - 告警：余额低于 $20 时邮件通知

说明：
  - 单用户频控在后端实现
  - Paymaster 不感知业务用户，不在此层做用户限额
```

---

## 八、监控告警体系

```go
type Metrics struct {
    SubscriptionCreatedTotal  prometheus.Counter
    RenewalSuccessRate        prometheus.Gauge
    RenewalFailureByReason    *prometheus.CounterVec  // label: reason
    CancellationTotal         prometheus.Counter
    ForceClosedTotal          prometheus.Counter
    CDPWalletAPILatency       prometheus.Histogram
    CDPPaymasterRejectRate    prometheus.Gauge
    MonthlyGasCostUSD         prometheus.Gauge
}

// 告警阈值
// - 续费成功率 < 95%            → PagerDuty P1
// - CDP API P99 延迟 > 5s       → PagerDuty P2
// - 链上事件监听延迟 > 5 分钟   → Slack 告警
// - 月度 gas 成本超预算 20%     → 邮件通知
// - Xray 同步失败率 > 1%        → PagerDuty P2
```

---

## 九、故障处理预案

### CDP 服务不可用

```
监控：CDP API 连续失败 > 3 次（30 秒内）触发告警
降级：暂停新订阅受理（503），已有订阅延长 grace period 24h（DB 层）
恢复：CDP 恢复后批量补发暂存交易
```

### 链上事件监听延迟

```
监控：事件延迟 > 5 分钟触发告警
修复：每 6 小时对账任务，扫描链上状态与 DB 对比
防护：关键操作（激活 VPN）等待链上状态二次确认
```

### 续费失败批量积压

```
提前预警：余额低于 2 期价格时提前 48h 通知
保护：给用户 3 次机会（后端 DB failCount），超限后停服
```

### 合约升级

```
方案：部署新合约，老合约 owner 调用 pause()
迁移：用户主动对新合约重新签名订阅，老订阅自然到期
过渡期：6 个月，之后停止老合约服务
```

---

## 十、费用结构（与 V2 对比）

| 费用项 | V2（自建 Relayer） | V3.3（CDP 托管） |
|---|---|---|
| Gas 来源 | 自持 ETH，手动充值 | CDP 月度账单，无需预充 |
| 服务费 | 无 | gas × 7%（约 $0.000007/笔） |
| 私钥管理 | 自建（KMS 或 Vault） | CDP 托管，无需 |
| Nonce/重试 | 自建 | CDP 自动 |
| 1000 用户/月总 gas 成本 | ~$0.50 ETH | ~$0.54（含 7% 服务费） |
| 开发工时差 | — | **节省约 1-2 周** |

---

## 十一、实施步骤

### Phase 1：CDP 账号配置（Day 1，约 2 小时）
- [ ] 注册 CDP 账号：[coinbase.com/developer-platform](https://www.coinbase.com/developer-platform)
- [ ] 创建 Server Wallet，记录 walletId
- [ ] 配置 Paymaster endpoint，设置合约白名单和全局月度上限
- [ ] **申请 Base Gasless Campaign gas credits（最高 $15,000）**

### Phase 2：智能合约（Week 1-2）
- [ ] 基于上方 Solidity 代码开发（EIP712 继承 + type hashes）
- [ ] Foundry 单测（覆盖率 > 95%），重点场景：
  - `SubscribeIntent` EIP-712 验签正常 / 伪造 / 重放
  - `CancelIntent` EIP-712 验签正常 / 伪造 / nonce 不匹配
  - `identityAddress` 唯一性（重复绑定应 revert）
  - `maxAmount >= plan.price` 校验
  - `permitDeadline >= block.timestamp` 校验
  - `executeRenewal` 使用快照价格，涨价不追溯
  - `executeRenewal` 套餐下架后老用户仍可续费
  - `executeRenewal` 到期前调用 revert（not yet expired）
  - `cancelSubscription / cancelFor` 后 `autoRenewEnabled=false`，`isActive` 仍为 true
  - `finalizeExpired` 自然到期路径（需 `!autoRenewEnabled && expiresAt <= now`）
  - `finalizeExpired` 强制停服路径（`forceClosed=true`，无时间限制）
  - `finalizeExpired` 后用户可重新发起订阅（`isActive=false`，`identityToOwner` 已释放）
  - struct slot 打包：uint96 不溢出（USDC max supply ≈ 1e14，远小于 2^96）
- [ ] 部署 Base Sepolia，BaseScan 验证合约

### Phase 3：后端（Week 2-3）
- [ ] 集成 CDP SDK
- [ ] `/api/intent-nonce`、`/api/cancel-nonce` 查询接口（含并发安全处理）
- [ ] `/api/subscribe`（IdempotencyKey + EIP-712 intentSig 双重验证）
- [ ] `/api/cancel`（频控 + EIP-712 cancelSig 验证）
- [ ] DB schema：identityAddress 唯一索引、idempotency_keys 表、renewal_fail_count 字段
- [ ] 定时任务：预检（到期前 24h）+ 续费（到期后）+ 终态清理（自然到期 / 强制停服）
- [ ] 链上事件监听（Created / Renewed / Cancelled / Expired / ForceClosed / RenewalFailed）
- [ ] 6 小时对账任务
- [ ] 监控埋点（Prometheus）
- [ ] 余额不足通知

### Phase 4：前端（Week 3-4）
- [ ] MetaMask 连接 + 余额预检
- [ ] SubscribeIntent EIP-712 + permit 双签名
- [ ] CancelIntent EIP-712 签名 + 提示"服务持续至到期日"
- [ ] 订阅状态展示（含 autoRenewEnabled）
- [ ] 错误处理和用户友好提示

### Phase 5：测试上线（Week 4-5）
- [ ] Base Sepolia 端到端测试（完整订阅→取消→到期→重新订阅路径）
- [ ] CDP Paymaster 策略验证
- [ ] 并发测试：同一 identityAddress 两个地址同时订阅（应有一个 revert）
- [ ] intentNonce 并发测试
- [ ] 主网部署

---

## 十二、参考资料

- [CDP Paymaster 文档](https://docs.cdp.coinbase.com/paymaster/introduction/welcome)
- [CDP Server Wallets 文档](https://docs.cdp.coinbase.com/wallets/server-wallets)
- [Base Gasless Campaign（$15K gas credits）](https://docs.base.org/identity/smart-wallet/introduction/base-gasless-campaign)
- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-2612 Permit 规范](https://eips.ethereum.org/EIPS/eip-2612)
- [OpenZeppelin EIP712 实现](https://docs.openzeppelin.com/contracts/5.x/api/utils#EIP712)
- [Shopify × CDP 案例（生产级参考）](https://www.coinbase.com/developer-platform/discover/launches/cdp-wallets-shopify)

---

## 十三、生产前补齐清单（不阻塞当前技术验证）

以下事项属于**生产化完善项**，不是当前 POC/技术验证阶段的核心技术阻塞点。它们**不阻塞现在开始开发和做技术验证**，但在主网上线前必须补齐。

### 13.1 治理与权限控制

当前合约中 `owner` 和 `relayer` 权限较大，POC 阶段可接受，但生产环境需要补充治理约束：

- `owner` 使用多签（如 2/3 Safe），避免单点私钥风险
- `setRelayer` / `setServiceWallet` / `setPlan` / `pause` 等关键操作纳入审批流程
- `finalizeExpired(user, true)` 强制停服路径保留操作审计日志
- 关键治理操作增加监控告警和人工复核

**结论**：这是生产治理问题，不影响当前核心链路验证。

### 13.2 链上状态、DB 状态、Xray 状态一致性

当前文档已经定义了事件监听、对账任务和补偿机制，足够支撑技术验证；但生产环境需要进一步细化一致性边界：

- Xray `AddUser` / `RemoveUser` 失败时的重试、死信和人工介入流程
- 链上交易成功但事件监听延迟/漏处理时的补偿路径
- Base 链重组场景下，以多少个 confirmation 作为最终成功标准
- DB 状态迁移与 Xray 实际状态不一致时的优先级判定

**结论**：这是生产可靠性设计，不阻塞 POC。

### 13.3 幂等性与崩溃恢复

当前文档已包含 `IdempotencyKey`、nonce、防重放和定时对账，适合验证主流程；但生产环境需要把“进程崩溃中断”考虑得更严：

- `SendTransaction` 成功但 `SaveIdempotencyKey` 前进程崩溃的恢复策略
- `cancelFor` / `finalizeExpired` 等异步任务的 crash-safe 幂等
- 是否引入事务型 outbox / job queue / durable scheduler
- 是否支持 CDP 请求侧幂等键或请求去重机制

**结论**：这是生产级健壮性问题，不阻塞当前开发推进。

### 13.4 到期、宽限期与停服业务规则

当前文档已把主逻辑收敛为“到期前 24h 预检、到期后续费、失败达到阈值后停服”，足够做技术验证；但生产前仍需和产品/客服/运营统一最终规则：

- 到期后是否允许短暂宽限期继续使用 VPN
- 第 1 次 / 第 2 次 / 第 3 次失败时前端显示什么状态
- 用户在失败重试期间是否仍可手动恢复续费
- 客服和通知口径如何定义“已过期”“待续费”“宽限期内”

**结论**：这是业务定稿问题，不影响底层技术验证。

### 13.5 外部依赖的真实验证

当前方案依赖 CDP Server Wallet、Paymaster、Base 网络和相关费率假设。文档设计已经可用于验证，但生产前必须完成真实环境验证：

- Base Sepolia 端到端跑通后，再验证 Base Mainnet 行为差异
- 验证 Paymaster 配额、拒绝策略、限流和错误码
- 验证 CDP 故障时的降级路径是否真实可用
- 验证实际 gas 成本、月账单和预算模型

**结论**：这是上线前验收项，不阻塞现在启动技术验证。

### 13.6 阶段性判断

可把当前方案按两个阶段理解：

1. **当前阶段：技术验证 / POC**
   - 目标：验证签名、订阅、取消、续费、终态清理主链路是否跑通
   - 结论：当前文档已足够支持这一阶段

2. **下一阶段：生产化完善**
   - 目标：补齐治理、幂等、监控、一致性、业务规则和主网验证
   - 结论：这些是上线前工作，不是当前开发阻塞项

**结论**：上述 5 类问题都不是当前核心技术难点，**不会阻塞你们现在的开发进度**；它们属于“POC 跑通之后，进入生产前必须补齐”的工作。

---

**文档作者**: Claude
**最后更新**: 2026-04-10
**状态**: V3.3 修订稿，三个 P0 问题已解决，可进入开发
