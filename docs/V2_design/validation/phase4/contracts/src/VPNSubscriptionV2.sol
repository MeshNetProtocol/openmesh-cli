// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title VPNSubscription V2
 * @notice 支持一个钱包为多个 VPN 身份订阅服务
 * @dev 核心改变：订阅索引从 `付款钱包 → 订阅` 改为 `VPN 身份 → 订阅`
 */
contract VPNSubscription is Ownable, Pausable, ReentrancyGuard, EIP712 {

    using ECDSA for bytes32;

    // ─── EIP-712 type hashes ───────────────────────────────────────────
    bytes32 private constant SUBSCRIBE_INTENT_TYPEHASH = keccak256(
        "SubscribeIntent(address user,address identityAddress,uint256 planId,uint256 maxAmount,uint256 deadline,uint256 nonce)"
    );
    bytes32 private constant CANCEL_INTENT_TYPEHASH = keccak256(
        "CancelIntent(address user,address identityAddress,uint256 nonce)"
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

    // ─── 订阅（✅ 修改：以 VPN 身份为 key）──────────────────────────
    struct Subscription {
        address identityAddress;   // VPN 身份地址
        address payerAddress;      // ✅ 新增：付款钱包地址
        uint96  lockedPrice;       // 锁定价格
        uint256 planId;            // 套餐 ID
        uint256 lockedPeriod;      // 锁定周期
        uint256 startTime;         // 开始时间
        uint256 expiresAt;         // 到期时间
        bool    autoRenewEnabled;  // 自动续费开关
        bool    isActive;          // 是否活跃
    }
    // ✅ 修改：以 VPN 身份为 key（而不是付款钱包）
    mapping(address => Subscription) public subscriptions;

    // ─── identity 唯一性 ───────────────────────────────────────────────
    // 防止同一 VPN 身份被多个付款地址绑定
    mapping(address => address) public identityToOwner;

    // ✅ 新增：付款钱包 → VPN 身份列表（用于查询用户的所有订阅）
    mapping(address => address[]) public userIdentities;

    // ─── 防重放 nonce ──────────────────────────────────────────────────
    mapping(address => uint256) public intentNonces; // SubscribeIntent
    mapping(address => uint256) public cancelNonces; // CancelIntent

    // ─── 事件 ──────────────────────────────────────────────────────────
    event SubscriptionCreated(
        address indexed payer,
        address indexed identity,
        uint256 planId,
        uint96  lockedPrice,
        uint256 lockedPeriod,
        uint256 expiresAt
    );
    event SubscriptionRenewed(address indexed payer, address indexed identity, uint256 newExpiresAt);
    event SubscriptionCancelled(address indexed payer, address indexed identity);
    event SubscriptionForceClosed(address indexed payer, address indexed identity);
    event SubscriptionExpired(address indexed payer, address indexed identity);
    event RenewalFailed(address indexed payer, address indexed identity, string reason);

    modifier onlyRelayer() {
        require(msg.sender == relayer, "VPN: not relayer");
        _;
    }

    constructor(
        address _usdc,
        address _serviceWallet,
        address _relayer
    ) Ownable(msg.sender) EIP712("VPNSubscription", "2") {
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

        // ✅ 修改：检查 VPN 身份是否已有订阅（而不是检查付款钱包）
        require(!subscriptions[identityAddress].isActive,   "VPN: identity already subscribed");
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

        // ✅ 修改：以 VPN 身份为 key 存储订阅，并记录付款钱包
        identityToOwner[identityAddress] = user;
        subscriptions[identityAddress] = Subscription({
            identityAddress:  identityAddress,
            payerAddress:     user,  // ✅ 新增：记录付款钱包
            lockedPrice:      uint96(plan.price),
            planId:           planId,
            lockedPeriod:     plan.period,
            startTime:        block.timestamp,
            expiresAt:        block.timestamp + plan.period,
            autoRenewEnabled: true,
            isActive:         true
        });

        // ✅ 新增：将身份添加到用户的身份列表
        userIdentities[user].push(identityAddress);

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
    /// @param identityAddress VPN 身份地址（✅ 修改：参数改为 identityAddress）
    function executeRenewal(address identityAddress) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.isActive,                               "VPN: not subscribed");
        require(sub.autoRenewEnabled,                       "VPN: auto renew disabled");
        require(block.timestamp >= sub.expiresAt,           "VPN: not yet expired");

        uint256 price  = uint256(sub.lockedPrice);
        uint256 period = sub.lockedPeriod;
        address payer  = sub.payerAddress;  // ✅ 修改：从订阅中获取付款钱包

        uint256 allowance = IERC20(address(usdc)).allowance(payer, address(this));
        uint256 balance   = IERC20(address(usdc)).balanceOf(payer);

        if (allowance < price) { emit RenewalFailed(payer, identityAddress, "insufficient allowance"); return; }
        if (balance   < price) { emit RenewalFailed(payer, identityAddress, "insufficient balance");   return; }

        // ✅ 修改：从付款钱包扣款（而不是从 identityAddress）
        require(
            IERC20(address(usdc)).transferFrom(payer, serviceWallet, price),
            "VPN: transfer failed"
        );
        sub.expiresAt = sub.expiresAt + period;

        emit SubscriptionRenewed(payer, identityAddress, sub.expiresAt);
    }

    // ─────────────────────────────────────────
    // 取消订阅（关闭自动续费）
    // ─────────────────────────────────────────

    /// @notice 用户亲自上链取消（需 gas）
    /// @param identityAddress VPN 身份地址（✅ 新增参数）
    function cancelSubscription(address identityAddress) external {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.isActive,           "VPN: not subscribed");
        require(sub.payerAddress == msg.sender, "VPN: not owner");  // ✅ 验证付款钱包
        require(sub.autoRenewEnabled,   "VPN: already cancelled");
        sub.autoRenewEnabled = false;
        emit SubscriptionCancelled(msg.sender, identityAddress);
    }

    /// @notice Relayer 代发取消（用户零 gas），使用 EIP-712 CancelIntent
    /// @param user 付款钱包地址
    /// @param identityAddress VPN 身份地址（✅ 新增参数）
    function cancelFor(
        address user,
        address identityAddress,
        uint256 nonce,
        bytes calldata sig
    ) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.isActive,           "VPN: not subscribed");
        require(sub.payerAddress == user, "VPN: not owner");  // ✅ 验证付款钱包
        require(sub.autoRenewEnabled,   "VPN: already cancelled");
        require(nonce == cancelNonces[user], "VPN: invalid nonce");

        // ── EIP-712 CancelIntent 验签 ──
        bytes32 structHash = keccak256(abi.encode(
            CANCEL_INTENT_TYPEHASH,
            user,
            identityAddress,
            nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(sig);
        require(signer == user,         "VPN: invalid signature");

        cancelNonces[user]++;
        sub.autoRenewEnabled = false;
        emit SubscriptionCancelled(user, identityAddress);
    }

    // ─────────────────────────────────────────
    // 终态清理
    // ─────────────────────────────────────────

    /// @notice 清理已到期的订阅，释放链上状态，允许用户重新订阅
    /// @param identityAddress VPN 身份地址（✅ 修改：参数改为 identityAddress）
    /// @param forceClosed true = 强制停服，false = 自然到期
    function finalizeExpired(address identityAddress, bool forceClosed)
        external onlyRelayer whenNotPaused nonReentrant
    {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.isActive,                               "VPN: not active");

        if (!forceClosed) {
            require(!sub.autoRenewEnabled,                  "VPN: auto renew still on");
            require(block.timestamp >= sub.expiresAt,       "VPN: not yet expired");
        }

        address payer = sub.payerAddress;
        sub.isActive = false;
        sub.autoRenewEnabled = false;
        identityToOwner[identityAddress] = address(0);

        // ✅ 新增：从用户的身份列表中移除
        _removeIdentityFromUser(payer, identityAddress);

        if (forceClosed) {
            emit SubscriptionForceClosed(payer, identityAddress);
        } else {
            emit SubscriptionExpired(payer, identityAddress);
        }
    }

    // ─────────────────────────────────────────
    // ✅ 新增：辅助函数
    // ─────────────────────────────────────────

    /// @notice 从用户的身份列表中移除指定身份
    function _removeIdentityFromUser(address user, address identityAddress) private {
        address[] storage identities = userIdentities[user];
        for (uint256 i = 0; i < identities.length; i++) {
            if (identities[i] == identityAddress) {
                identities[i] = identities[identities.length - 1];
                identities.pop();
                break;
            }
        }
    }

    /// @notice 查询用户的所有订阅身份
    function getUserIdentities(address user) external view returns (address[] memory) {
        return userIdentities[user];
    }

    /// @notice 查询用户的所有活跃订阅
    function getUserActiveSubscriptions(address user) external view returns (Subscription[] memory) {
        address[] memory identities = userIdentities[user];
        uint256 activeCount = 0;

        // 统计活跃订阅数量
        for (uint256 i = 0; i < identities.length; i++) {
            if (subscriptions[identities[i]].isActive) {
                activeCount++;
            }
        }

        // 构建活跃订阅数组
        Subscription[] memory activeSubscriptions = new Subscription[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < identities.length; i++) {
            if (subscriptions[identities[i]].isActive) {
                activeSubscriptions[index] = subscriptions[identities[i]];
                index++;
            }
        }

        return activeSubscriptions;
    }

    // ─────────────────────────────────────────
    // Owner 管理
    // ─────────────────────────────────────────

    function setPlan(uint256 id, uint256 price, uint256 period, bool active) external onlyOwner {
        require(price <= type(uint96).max, "VPN: price too large");
        plans[id] = Plan(price, period, active);
    }
    function setRelayer(address r) external onlyOwner { relayer = r; }
    function setServiceWallet(address w) external onlyOwner { serviceWallet = w; }
    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
