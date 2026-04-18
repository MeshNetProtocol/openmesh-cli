// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IUSDC3009 {
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @title VPNSubscription V2
 * @notice 支持一个钱包为多个 VPN 身份订阅服务
 * @dev 核心改变：订阅索引从 `付款钱包 → 订阅` 改为 `VPN 身份 → 订阅`
 */
contract VPNSubscription is Ownable, Pausable, ReentrancyGuard, EIP712 {

    using ECDSA for bytes32;

    // ─── EIP-712 type hashes ───────────────────────────────────────────
    bytes32 private constant SUBSCRIBE_INTENT_TYPEHASH = keccak256(
        "SubscribeIntent(address user,address identityAddress,uint256 planId,bool isYearly,uint256 maxAmount,uint256 deadline,uint256 nonce)"
    );
    bytes32 private constant CANCEL_INTENT_TYPEHASH = keccak256(
        "CancelIntent(address user,address identityAddress,uint256 nonce)"
    );

    // ✅ V2.1: 订阅变更签名类型
    bytes32 private constant UPGRADE_INTENT_TYPEHASH = keccak256(
        "UpgradeIntent(address user,address identityAddress,uint256 newPlanId,bool isYearly,uint256 maxAmount,uint256 deadline,uint256 nonce)"
    );

    // ✅ V2.5: 降级签名类型
    bytes32 private constant DOWNGRADE_INTENT_TYPEHASH = keccak256(
        "DowngradeIntent(address user,address identityAddress,uint256 newPlanId,uint256 nonce)"
    );

    // ─── 常量 ──────────────────────────────────────────────────────────
    IERC20Permit public immutable usdc;
    uint256 public constant USDC_UNIT = 1e6;

    // ─── 可配置 ────────────────────────────────────────────────────────
    address public serviceWallet;
    address public relayer;

    uint256 public constant RENEWAL_GRACE_PERIOD = 3 days;

    // ─── 套餐 ──────────────────────────────────────────────────────────
    struct Plan {
        string  name;                  // 套餐名称
        uint256 pricePerMonth;         // 月价格 (USDC, 6 decimals)
        uint256 pricePerYear;          // 年价格 (USDC, 6 decimals)
        uint256 period;                // 默认周期
        uint8   tier;                  // 套餐等级 (用于判断升级/降级)
        bool    isActive;              // 是否可用
    }
    mapping(uint256 => Plan) public plans;
    mapping(uint8 => uint256) public tierToPlanId;  // tier -> planId 映射，确保每个 tier 只有一个套餐

    // ─── 订阅（✅ 修改：以 VPN 身份为 key）──────────────────────────
    struct Subscription {
        address identityAddress;   // VPN 身份地址
        address payerAddress;      // ✅ 新增：付款钱包地址
        uint96  lockedPrice;       // 锁定价格
        uint256 planId;            // 套餐 ID
        uint256 lockedPeriod;      // 锁定周期
        uint256 startTime;         // 开始时间
        uint256 expiresAt;         // 到期时间
        uint256 renewedAt;         // 最近一次续费时间
        bool    autoRenewEnabled;  // 自动续费开关
        uint256 nextPlanId;        // 待生效的降级套餐 ID (0 = 无降级)
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
    event RenewalFailed(address indexed payer, address indexed identity, string reason);
    event SubscriptionUpgraded(address indexed payer, address indexed identity, uint256 newPlanId, uint256 additionalPayment);
    event SubscriptionDowngraded(address indexed payer, address indexed identity, uint256 newPlanId);

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

        // ✅ V2.6: 套餐由 owner 通过 setPlan() 动态管理，构造函数不再初始化套餐
    }

    // ─────────────────────────────────────────
    // 订阅
    // ─────────────────────────────────────────

    /// @notice 首次订阅
    /// @param user             付款地址
    /// @param identityAddress  VPN 准入身份（链上唯一性校验）
    /// @param planId           套餐 ID
    /// @param isYearly         是否年付
    /// @param maxAmount        用户确认的 permit 授权上限（== permit value）
    /// @param permitDeadline   permit 截止时间（== SubscribeIntent deadline）
    /// @param intentNonce      SubscribeIntent 防重放 nonce（== intentNonces[user]）
    /// @param intentSig        用户对 SubscribeIntent 的 EIP-712 签名
    /// @param permitV/R/S      ERC-2612 permit 签名
    function permitAndSubscribe(
        address user,
        address identityAddress,
        uint256 planId,
        bool isYearly,
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

        // ✅ V2.2: 检查 VPN 身份是否已有有效订阅（通过到期时间判断）
        require(subscriptions[identityAddress].expiresAt <= block.timestamp, "VPN: identity already subscribed");

        // ✅ V2.1: 根据套餐类型确定价格和周期（月付或年付）
        uint256 price = isYearly ? plan.pricePerYear : plan.pricePerMonth;
        uint256 period = isYearly ? 365 days : plan.period;

        require(maxAmount >= price,                         "VPN: maxAmount too low");
        require(price <= type(uint96).max,                  "VPN: price overflow");

        // ── EIP-712 SubscribeIntent 验签 ──
        require(intentNonce == intentNonces[user],          "VPN: invalid intent nonce");
        bytes32 structHash = keccak256(abi.encode(
            SUBSCRIBE_INTENT_TYPEHASH,
            user,
            identityAddress,
            planId,
            isYearly,
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
            IERC20(address(usdc)).transferFrom(user, serviceWallet, price),
            "VPN: transfer failed"
        );

        // ✅ 修改：以 VPN 身份为 key 存储订阅，并记录付款钱包
        identityToOwner[identityAddress] = user;
        subscriptions[identityAddress] = Subscription({
            identityAddress:  identityAddress,
            payerAddress:     user,  // ✅ 新增：记录付款钱包
            lockedPrice:      uint96(price),
            planId:           planId,
            lockedPeriod:     period,
            startTime:        block.timestamp,
            expiresAt:        block.timestamp + period,
            renewedAt:        block.timestamp,
            autoRenewEnabled: true,
            nextPlanId:       0  // ✅ V2.5: 初始化为 0（无降级）
        });

        // ✅ 新增：将身份添加到用户的身份列表（避免重复添加）
        if (userIdentities[user].length == 0 || !_identityExists(user, identityAddress)) {
            userIdentities[user].push(identityAddress);
        }

        emit SubscriptionCreated(
            user, identityAddress, planId,
            uint96(price), period,
            block.timestamp + period
        );
    }

    // ─────────────────────────────────────────
    // 链上续费
    // ─────────────────────────────────────────

    /// @notice 到期后由 Relayer 发起续费
    /// @param identityAddress VPN 身份地址（✅ 修改：参数改为 identityAddress）
    function executeRenewal(address identityAddress) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > 0,                          "VPN: not subscribed");
        require(sub.autoRenewEnabled,                       "VPN: auto renew disabled");
        require(block.timestamp >= sub.expiresAt,           "VPN: renewal not due");
        require(block.timestamp <= sub.expiresAt + RENEWAL_GRACE_PERIOD, "VPN: renewal window passed");
        require(block.timestamp >= sub.renewedAt + sub.lockedPeriod, "VPN: renewed too recently");

        address payer = sub.payerAddress;

        // ✅ V2.5: 检查是否有待生效的降级
        uint256 renewalPlanId = sub.nextPlanId > 0 ? sub.nextPlanId : sub.planId;
        Plan memory plan = plans[renewalPlanId];
        require(plan.isActive, "VPN: plan not active");

        uint256 price = plan.pricePerMonth;
        uint256 period = plan.period;

        uint256 allowance = IERC20(address(usdc)).allowance(payer, address(this));
        uint256 balance   = IERC20(address(usdc)).balanceOf(payer);

        if (allowance < price) { emit RenewalFailed(payer, identityAddress, "insufficient allowance"); return; }
        if (balance   < price) { emit RenewalFailed(payer, identityAddress, "insufficient balance");   return; }

        require(
            IERC20(address(usdc)).transferFrom(payer, serviceWallet, price),
            "VPN: transfer failed"
        );

        // ✅ V2.5: 创建新的订阅对象（而不是更新现有的）
        uint256 renewalBase = block.timestamp > sub.expiresAt ? block.timestamp : sub.expiresAt;
        subscriptions[identityAddress] = Subscription({
            identityAddress: identityAddress,
            payerAddress: payer,
            lockedPrice: uint96(price),
            planId: renewalPlanId,
            lockedPeriod: period,
            startTime: renewalBase,
            expiresAt: renewalBase + period,
            renewedAt: block.timestamp,
            autoRenewEnabled: true,
            nextPlanId: 0
        });

        emit SubscriptionRenewed(payer, identityAddress, renewalBase + period);
    }

    // ─────────────────────────────────────────
    // 取消订阅（关闭自动续费）
    // ─────────────────────────────────────────

    /// @notice 用户亲自上链取消（需 gas）
    /// @param identityAddress VPN 身份地址（✅ 新增参数）
    function cancelSubscription(address identityAddress) external {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > 0,      "VPN: not subscribed");  // ✅ V2.2: 通过 expiresAt 判断
        require(sub.payerAddress == msg.sender, "VPN: not owner");
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
        require(sub.expiresAt > 0,      "VPN: not subscribed");  // ✅ V2.2: 通过 expiresAt 判断
        require(sub.payerAddress == user, "VPN: not owner");
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
    // ✅ V2.1: Proration 算法
    // ─────────────────────────────────────────

    /// @notice 计算升级补差价
    /// @param identityAddress VPN 身份地址
    /// @param newPlanId 新套餐 ID
    /// @param isYearly 是否年付
    /// @return additionalPayment 需要补缴的金额
    function calculateUpgradeProration(
        address identityAddress,
        uint256 newPlanId,
        bool isYearly
    ) public view returns (uint256 additionalPayment) {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > block.timestamp, "VPN: not active");  // ✅ V2.2: 通过到期时间判断

        Plan memory currentPlan = plans[sub.planId];
        Plan memory newPlan = plans[newPlanId];

        require(newPlan.tier > currentPlan.tier, "VPN: not an upgrade");
        require(newPlan.isActive, "VPN: new plan not active");

        // 计算剩余时间
        uint256 remainingTime = sub.expiresAt > block.timestamp
            ? sub.expiresAt - block.timestamp
            : 0;
        require(remainingTime > 0, "VPN: subscription expired");

        uint256 totalPeriod = sub.lockedPeriod;

        // 当前套餐剩余价值 (按时间比例)
        uint256 currentValue = (uint256(sub.lockedPrice) * remainingTime) / totalPeriod;

        // 新套餐对应周期的价值
        uint256 newPrice = isYearly ? newPlan.pricePerYear : newPlan.pricePerMonth;
        uint256 newValue = (newPrice * remainingTime) / totalPeriod;

        // 补差价
        if (newValue > currentValue) {
            additionalPayment = newValue - currentValue;
        } else {
            additionalPayment = 0; // 不退款
        }
    }

    // ─────────────────────────────────────────
    // ✅ V2.1: 订阅变更函数
    // ─────────────────────────────────────────

    /// @notice 升级订阅 (立即生效 + Proration)
    /// @param user 付款地址
    /// @param identityAddress VPN 身份地址
    /// @param newPlanId 新套餐 ID
    /// @param isYearly 是否年付
    /// @param maxAmount 用户确认的最大支付金额
    /// @param deadline 签名截止时间
    /// @param nonce 防重放 nonce
    /// @param intentSig EIP-712 签名
    /// @param permitV/R/S ERC-2612 permit 签名
    function upgradeSubscription(
        address user,
        address identityAddress,
        uint256 newPlanId,
        bool isYearly,
        uint256 maxAmount,
        uint256 deadline,
        uint256 nonce,
        bytes calldata intentSig,
        uint8 permitV, bytes32 permitR, bytes32 permitS
    ) external onlyRelayer whenNotPaused nonReentrant {
        require(deadline >= block.timestamp, "VPN: deadline expired");

        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > block.timestamp, "VPN: not active");  // ✅ V2.2: 通过到期时间判断
        require(sub.payerAddress == user, "VPN: not owner");

        Plan memory newPlan = plans[newPlanId];
        require(newPlan.isActive, "VPN: new plan not active");
        require(newPlan.tier > plans[sub.planId].tier, "VPN: not an upgrade");

        // EIP-712 签名验证
        require(nonce == intentNonces[user], "VPN: invalid nonce");
        bytes32 structHash = keccak256(abi.encode(
            UPGRADE_INTENT_TYPEHASH,
            user,
            identityAddress,
            newPlanId,
            isYearly,
            maxAmount,
            deadline,
            nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(intentSig);
        require(signer == user, "VPN: invalid signature");
        intentNonces[user]++;

        // 计算补差价
        uint256 additionalPayment = calculateUpgradeProration(identityAddress, newPlanId, isYearly);
        require(additionalPayment <= maxAmount, "VPN: exceeds maxAmount");

        if (additionalPayment > 0) {
            // ERC-2612 permit
            usdc.permit(user, address(this), maxAmount, deadline, permitV, permitR, permitS);

            // 扣款
            require(
                IERC20(address(usdc)).transferFrom(user, serviceWallet, additionalPayment),
                "VPN: transfer failed"
            );
        }

        // 更新订阅
        uint256 newPrice = isYearly ? newPlan.pricePerYear : newPlan.pricePerMonth;
        uint256 newPeriod = isYearly ? 365 days : 30 days;

        sub.planId = newPlanId;
        sub.lockedPrice = uint96(newPrice);
        sub.lockedPeriod = newPeriod;
        // expiresAt 保持不变 (立即生效,不延长周期)

        emit SubscriptionUpgraded(user, identityAddress, newPlanId, additionalPayment);
    }

    /**
     * @notice 降级订阅（标记待生效，下次续费时切换）
     * @dev 降级不立即生效，不退款，等到期后续费时自动切换到新套餐
     */
    function downgradeSubscription(
        address user,
        address identityAddress,
        uint256 newPlanId,
        uint256 nonce,
        bytes calldata signature
    ) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > block.timestamp, "VPN: not active");
        require(sub.payerAddress == user, "VPN: not owner");

        Plan memory newPlan = plans[newPlanId];
        require(newPlan.isActive, "VPN: new plan not active");
        require(newPlan.tier < plans[sub.planId].tier, "VPN: not a downgrade");

        // EIP-712 签名验证
        require(nonce == intentNonces[user], "VPN: invalid nonce");
        bytes32 structHash = keccak256(abi.encode(
            DOWNGRADE_INTENT_TYPEHASH,
            user,
            identityAddress,
            newPlanId,
            nonce
        ));
        address signer = _hashTypedDataV4(structHash).recover(signature);
        require(signer == user, "VPN: invalid signature");
        intentNonces[user]++;

        // 设置待生效的降级套餐
        sub.nextPlanId = newPlanId;

        emit SubscriptionDowngraded(user, identityAddress, newPlanId);
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

        // 统计活跃订阅数量（✅ V2.2: 通过到期时间判断）
        for (uint256 i = 0; i < identities.length; i++) {
            Subscription storage sub = subscriptions[identities[i]];
            if (sub.expiresAt > block.timestamp) {
                activeCount++;
            }
        }

        // 构建活跃订阅数组
        Subscription[] memory activeSubs = new Subscription[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < identities.length; i++) {
            Subscription storage sub = subscriptions[identities[i]];
            if (sub.expiresAt > block.timestamp) {
                activeSubs[index] = sub;
                index++;
            }
        }

        return activeSubs;
    }

    // ─────────────────────────────────────────
    // EIP-3009 续费
    // ─────────────────────────────────────────

    /// @notice 使用 EIP-3009 transferWithAuthorization 续费（零 Gas 给用户）
    /// @dev Relayer 提交签名，USDC 直接从用户转到 serviceWallet
    /// @param identityAddress VPN 身份地址
    /// @param validAfter  签名生效时间（Unix 秒）
    /// @param validBefore 签名失效时间（Unix 秒）
    /// @param nonce       bytes32 随机 nonce（EIP-3009 独立，不影响 EIP-2612 nonce）
    /// @param v r s       用户的 EIP-712 签名
    function renewWithAuthorization(
        address identityAddress,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v, bytes32 r, bytes32 s
    ) external onlyRelayer whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[identityAddress];
        require(sub.expiresAt > 0, "VPN: not subscribed");  // ✅ V2.2: 通过 expiresAt 判断是否有订阅
        require(sub.autoRenewEnabled,    "VPN: auto renew disabled");
        require(block.timestamp >= sub.expiresAt, "VPN: renewal not due");
        require(block.timestamp <= sub.expiresAt + RENEWAL_GRACE_PERIOD, "VPN: renewal window passed");
        require(block.timestamp >= sub.renewedAt + sub.lockedPeriod, "VPN: renewed too recently");

        address payer = sub.payerAddress;
        uint256 price = uint256(sub.lockedPrice);

        // EIP-3009: 直接从 payer 转到 serviceWallet，无需 allowance
        IUSDC3009(address(usdc)).transferWithAuthorization(
            payer,
            serviceWallet,
            price,
            validAfter,
            validBefore,
            nonce,
            v, r, s
        );

        uint256 renewalBase = block.timestamp > sub.expiresAt ? block.timestamp : sub.expiresAt;
        uint256 newExpiresAt = renewalBase + sub.lockedPeriod;
        sub.renewedAt = block.timestamp;
        sub.expiresAt = newExpiresAt;
        emit SubscriptionRenewed(payer, identityAddress, sub.expiresAt);
    }

    // ─────────────────────────────────────────
    // Owner 管理
    // ─────────────────────────────────────────

    /// @notice 添加/更新套餐
    /// @dev ✅ V2.5: 简化 Plan 结构，删除流量字段
    function setPlan(
        uint256 id,
        string memory name,
        uint256 pricePerMonth,
        uint256 pricePerYear,
        uint256 period,
        uint8 tier,
        bool active
    ) external onlyOwner {
        require(pricePerMonth <= type(uint96).max, "VPN: price too large");
        require(pricePerYear <= type(uint96).max, "VPN: price too large");
        require(tier > 0, "VPN: tier must be > 0");

        // ✅ V2.6: 检查 tier 唯一性
        uint256 existingPlanId = tierToPlanId[tier];
        require(existingPlanId == 0 || existingPlanId == id, "VPN: tier already occupied");

        // 如果是更新现有套餐且 tier 改变，清理旧 tier 映射
        Plan storage oldPlan = plans[id];
        if (oldPlan.tier != 0 && oldPlan.tier != tier) {
            delete tierToPlanId[oldPlan.tier];
        }

        plans[id] = Plan({
            name: name,
            pricePerMonth: pricePerMonth,
            pricePerYear: pricePerYear,
            period: period,
            tier: tier,
            isActive: active
        });

        tierToPlanId[tier] = id;
    }

    /// @notice 禁用套餐
    function disablePlan(uint256 planId) external onlyOwner {
        require(plans[planId].isActive, "VPN: plan not active");
        plans[planId].isActive = false;
    }

    /// @notice 删除套餐
    /// @dev 删除套餐会清理 tier 映射，允许该 tier 被其他套餐使用
    function deletePlan(uint256 planId) external onlyOwner {
        Plan storage plan = plans[planId];
        require(plan.tier != 0, "VPN: plan not exists");

        // 清理 tier 映射
        delete tierToPlanId[plan.tier];

        // 删除套餐
        delete plans[planId];
    }

    /// @notice 查询套餐详情
    function getPlan(uint256 planId) external view returns (Plan memory) {
        return plans[planId];
    }

    // ─────────────────────────────────────────
    // ✅ V2.3: 活跃订阅列表管理
    // ─────────────────────────────────────────

    /// @notice 查询订阅详情
    function getSubscription(address identityAddress) external view returns (Subscription memory) {
        return subscriptions[identityAddress];
    }

    /// @notice 检查 identity 是否已存在于用户的身份列表中
    function _identityExists(address user, address identityAddress) private view returns (bool) {
        address[] memory identities = userIdentities[user];
        for (uint256 i = 0; i < identities.length; i++) {
            if (identities[i] == identityAddress) {
                return true;
            }
        }
        return false;
    }

    function setRelayer(address r) external onlyOwner { relayer = r; }
    function setServiceWallet(address w) external onlyOwner { serviceWallet = w; }
    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
