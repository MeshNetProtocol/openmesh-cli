// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
