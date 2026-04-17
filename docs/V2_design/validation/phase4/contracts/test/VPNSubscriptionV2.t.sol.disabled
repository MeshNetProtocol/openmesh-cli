// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VPNSubscriptionV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Alias the contract for clarity in tests
import {VPNSubscription as VPNSubscriptionV2} from "../src/VPNSubscriptionV2.sol";

// Mock USDC with ERC-2612 permit support
contract MockUSDC is ERC20 {
    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor() ERC20("USD Coin", "USDC") {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("USD Coin")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "USDC: permit expired");

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "USDC: invalid signature");

        _approve(owner, spender, value);
    }
}

contract VPNSubscriptionV2Test is Test {
    VPNSubscriptionV2 public vpn;
    MockUSDC public usdc;

    address public owner;
    address public relayer;
    address public serviceWallet;
    address public user;
    address public identity1;
    address public identity2;

    uint256 public userPrivateKey;

    bytes32 public DOMAIN_SEPARATOR;

    function setUp() public {
        owner = address(this);
        relayer = vm.addr(1);
        serviceWallet = vm.addr(2);
        userPrivateKey = 0x1234;
        user = vm.addr(userPrivateKey);
        identity1 = vm.addr(3);
        identity2 = vm.addr(4);

        usdc = new MockUSDC();
        vpn = new VPNSubscriptionV2(address(usdc), serviceWallet, relayer);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VPNSubscription")),
                keccak256(bytes("2")),
                block.chainid,
                address(vpn)
            )
        );

        usdc.mint(user, 10000 * 1e6); // 10000 USDC
    }

    // ============================================
    // Helper Functions
    // ============================================

    function signSubscribeIntent(
        uint256 privateKey,
        address _user,
        address _identity,
        uint256 planId,
        bool isYearly,
        uint256 maxAmount,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("SubscribeIntent(address user,address identityAddress,uint256 planId,bool isYearly,uint256 maxAmount,uint256 deadline,uint256 nonce)"),
                _user,
                _identity,
                planId,
                isYearly,
                maxAmount,
                deadline,
                nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signUpgradeIntent(
        uint256 privateKey,
        address _user,
        address _identity,
        uint256 newPlanId,
        bool isYearly,
        uint256 maxAmount,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("UpgradeIntent(address user,address identityAddress,uint256 newPlanId,bool isYearly,uint256 maxAmount,uint256 deadline,uint256 nonce)"),
                _user,
                _identity,
                newPlanId,
                isYearly,
                maxAmount,
                deadline,
                nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signDowngradeIntent(
        uint256 privateKey,
        address _user,
        address _identity,
        uint256 newPlanId,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("DowngradeIntent(address user,address identityAddress,uint256 newPlanId,uint256 nonce)"),
                _user,
                _identity,
                newPlanId,
                nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signCancelChangeIntent(
        uint256 privateKey,
        address _user,
        address _identity,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("CancelChangeIntent(address user,address identityAddress,uint256 nonce)"),
                _user,
                _identity,
                nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signPermit(
        uint256 privateKey,
        address _owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                usdc.PERMIT_TYPEHASH(),
                _owner,
                spender,
                value,
                usdc.nonces(_owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(privateKey, digest);
    }

    function subscribeToPremiumPlan() internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 10 * 1e6;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity1, 3, false, maxAmount, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity1, 3, false, maxAmount, deadline, 0, intentSig, v, r, s);
    }

    function subscribeToBasicPlan() internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 5 * 1e6;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity1, 2, false, maxAmount, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity1, 2, false, maxAmount, deadline, 0, intentSig, v, r, s);
    }

    // ============================================
    // Test: Plan Management
    // ============================================

    function testInitialPlansAreConfigured() public view {
        // Check Basic plan
        VPNSubscriptionV2.Plan memory basicPlan = vpn.getPlan(2);
        assertEq(basicPlan.name, "Basic");
        assertEq(basicPlan.pricePerMonth, 5 * 1e6);
        assertEq(basicPlan.pricePerYear, 50 * 1e6);
        assertEq(basicPlan.trafficLimitDaily, 0);
        assertEq(basicPlan.trafficLimitMonthly, 100 * 1024 * 1024 * 1024); // 100 GB
        assertEq(basicPlan.tier, 1);
        assertTrue(basicPlan.isActive);

        // Check Premium plan
        VPNSubscriptionV2.Plan memory premiumPlan = vpn.getPlan(3);
        assertEq(premiumPlan.name, "Premium");
        assertEq(premiumPlan.pricePerMonth, 10 * 1e6);
        assertEq(premiumPlan.pricePerYear, 100 * 1e6);
        assertEq(premiumPlan.trafficLimitDaily, 0);
        assertEq(premiumPlan.trafficLimitMonthly, 0);
        assertEq(premiumPlan.tier, 2);
        assertTrue(premiumPlan.isActive);

        // Check Test plan
        VPNSubscriptionV2.Plan memory testPlan = vpn.getPlan(4);
        assertEq(testPlan.name, "Test");
        assertEq(testPlan.pricePerMonth, 100000);
        assertEq(testPlan.period, 1800);
        assertEq(testPlan.tier, 99);
        assertTrue(testPlan.isActive);
    }

    function testSetPlan() public {
        vpn.setPlan(5, "Enterprise", 20 * 1e6, 200 * 1e6, 30 days, 0, 0, 3, true);

        VPNSubscriptionV2.Plan memory plan = vpn.getPlan(5);
        assertEq(plan.name, "Enterprise");
        assertEq(plan.pricePerMonth, 20 * 1e6);
        assertEq(plan.pricePerYear, 200 * 1e6);
        assertEq(plan.tier, 3);
        assertTrue(plan.isActive);
    }

    function testDisablePlan() public {
        vpn.disablePlan(2);

        VPNSubscriptionV2.Plan memory plan = vpn.getPlan(2);
        assertFalse(plan.isActive);
    }

    function testOnlyOwnerCanSetPlan() public {
        vm.prank(user);
        vm.expectRevert();
        vpn.setPlan(5, "Enterprise", 20 * 1e6, 200 * 1e6, 30 days, 0, 0, 3, true);
    }

    function testOnlyOwnerCanDisablePlan() public {
        vm.prank(user);
        vm.expectRevert();
        vpn.disablePlan(2);
    }

    // ============================================
    // Test: Traffic Management
    // ============================================

    function testReportTrafficUsage() public {
        subscribeToBasicPlan();

        uint256 bytesUsed = 50 * 1024 * 1024 * 1024; // 50 GB

        vm.prank(relayer);
        vpn.reportTrafficUsage(identity1, bytesUsed);

        (bool isWithinLimit, uint256 dailyRemaining, uint256 monthlyRemaining) = vpn.checkTrafficLimit(identity1);
        assertTrue(isWithinLimit);
        assertEq(dailyRemaining, 0);
        assertEq(monthlyRemaining, 50 * 1024 * 1024 * 1024); // 50 GB remaining
    }

    function testTrafficLimitExceeded() public {
        subscribeToBasicPlan();

        uint256 bytesUsed = 101 * 1024 * 1024 * 1024; // 101 GB (exceeds 100 GB limit)

        vm.prank(relayer);
        vm.expectEmit(true, true, true, false);
        emit VPNSubscriptionV2.TrafficLimitExceeded(user, identity1, false, bytesUsed);
        vpn.reportTrafficUsage(identity1, bytesUsed);

        (bool isWithinLimit,,) = vpn.checkTrafficLimit(identity1);
        assertFalse(isWithinLimit);
    }

    function testSuspendForTrafficLimit() public {
        subscribeToBasicPlan();

        vm.prank(relayer);
        vpn.suspendForTrafficLimit(identity1);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertTrue(sub.isSuspended);  // ✅ V2.2: 检查暂停标志而不是 isActive
    }

    function testResumeAfterReset() public {
        subscribeToBasicPlan();

        // Suspend
        vm.prank(relayer);
        vpn.suspendForTrafficLimit(identity1);

        // Resume
        vm.prank(relayer);
        vpn.resumeAfterReset(identity1);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertFalse(sub.isSuspended);  // ✅ V2.2: 检查暂停标志而不是 isActive
    }

    function testResetDailyTraffic() public {
        subscribeToBasicPlan();

        // Use some traffic
        vm.prank(relayer);
        vpn.reportTrafficUsage(identity1, 1024);

        // Reset
        vm.prank(relayer);
        vpn.resetDailyTraffic(identity1);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.trafficUsedDaily, 0);
    }

    function testResetMonthlyTraffic() public {
        subscribeToBasicPlan();

        // Use some traffic
        vm.prank(relayer);
        vpn.reportTrafficUsage(identity1, 10 * 1024 * 1024 * 1024); // 10 GB

        // Reset
        vm.prank(relayer);
        vpn.resetMonthlyTraffic(identity1);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.trafficUsedMonthly, 0);
    }

    function testOnlyRelayerCanReportTraffic() public {
        subscribeToBasicPlan();

        vm.prank(user);
        vm.expectRevert("VPN: not relayer");
        vpn.reportTrafficUsage(identity1, 1000);
    }

    function testOnlyRelayerCanSuspend() public {
        subscribeToBasicPlan();

        vm.prank(user);
        vm.expectRevert("VPN: not relayer");
        vpn.suspendForTrafficLimit(identity1);
    }

    // ============================================
    // Test: Proration Algorithm
    // ============================================

    function testCalculateUpgradeProration() public {
        subscribeToBasicPlan();

        // Warp to 15 days later (half of 30-day period)
        vm.warp(block.timestamp + 15 days);

        // Calculate proration for upgrade to Premium (monthly)
        uint256 additionalPayment = vpn.calculateUpgradeProration(identity1, 3, false);

        // Expected: (10 USDC × 15 days / 30 days) - (5 USDC × 15 days / 30 days)
        // = 5 USDC - 2.5 USDC = 2.5 USDC
        assertEq(additionalPayment, 2.5 * 1e6);
    }

    function testCalculateUpgradeProrationYearly() public {
        subscribeToBasicPlan();

        vm.warp(block.timestamp + 15 days);

        // Calculate proration for upgrade to Premium (yearly)
        uint256 additionalPayment = vpn.calculateUpgradeProration(identity1, 3, true);

        // Expected: (100 USDC × 15 days / 30 days) - (5 USDC × 15 days / 30 days)
        // = 50 USDC - 2.5 USDC = 47.5 USDC
        assertEq(additionalPayment, 47.5 * 1e6);
    }

    function testCalculateUpgradeProrationAtStart() public {
        subscribeToBasicPlan();

        // Calculate immediately after subscription
        uint256 additionalPayment = vpn.calculateUpgradeProration(identity1, 3, false);

        // Expected: (10 USDC × 30 days / 30 days) - (5 USDC × 30 days / 30 days)
        // = 10 USDC - 5 USDC = 5 USDC
        assertEq(additionalPayment, 5 * 1e6);
    }

    function testCalculateUpgradeProrationNearEnd() public {
        subscribeToBasicPlan();

        // Warp to 29 days later (1 day remaining)
        vm.warp(block.timestamp + 29 days);

        uint256 additionalPayment = vpn.calculateUpgradeProration(identity1, 3, false);

        // Expected: (10 USDC × 1 day / 30 days) - (5 USDC × 1 day / 30 days)
        // ≈ 0.333 USDC - 0.167 USDC ≈ 0.166 USDC
        assertApproxEqAbs(additionalPayment, 0.166 * 1e6, 0.01 * 1e6);
    }

    function testCannotCalculateProrationForDowngrade() public {
        subscribeToBasicPlan();

        vm.expectRevert("VPN: not an upgrade");
        vpn.calculateUpgradeProration(identity1, 1, false);
    }

    // ============================================
    // Test: Subscription Upgrade
    // ============================================

    function testUpgradeSubscription() public {
        subscribeToBasicPlan();

        vm.warp(block.timestamp + 15 days);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 10 * 1e6;
        bytes memory intentSig = signUpgradeIntent(
            userPrivateKey, user, identity1, 3, false, maxAmount, deadline, 1
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        uint256 balanceBefore = usdc.balanceOf(serviceWallet);

        vm.prank(relayer);
        vpn.upgradeSubscription(user, identity1, 3, false, maxAmount, deadline, 1, intentSig, v, r, s);

        // Verify plan changed
        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.planId, 3);

        // Verify payment (should be ~2.5 USDC proration)
        assertApproxEqAbs(usdc.balanceOf(serviceWallet), balanceBefore + 2.5 * 1e6, 0.01 * 1e6);
    }

    function testUpgradeSubscriptionYearly() public {
        subscribeToBasicPlan();

        vm.warp(block.timestamp + 15 days);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 100 * 1e6;
        bytes memory intentSig = signUpgradeIntent(
            userPrivateKey, user, identity1, 3, true, maxAmount, deadline, 1
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.upgradeSubscription(user, identity1, 3, true, maxAmount, deadline, 1, intentSig, v, r, s);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.planId, 3);
        assertEq(sub.lockedPeriod, 365 days);
    }

    function testCannotUpgradeToLowerTier() public {
        subscribeToBasicPlan();

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory intentSig = signUpgradeIntent(
            userPrivateKey, user, identity1, 1, false, 0, deadline, 1
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), 0, deadline);

        vm.prank(relayer);
        vm.expectRevert("VPN: new plan not active");
        vpn.upgradeSubscription(user, identity1, 1, false, 0, deadline, 1, intentSig, v, r, s);
    }

    // ============================================
    // Test: Subscription Downgrade
    // ============================================

    function testDowngradeSubscription() public {
        subscribeToPremiumPlan();

        bytes memory intentSig = signDowngradeIntent(userPrivateKey, user, identity1, 2, 1);

        vm.prank(relayer);
        vpn.downgradeSubscription(user, identity1, 2, 1, intentSig);

        // Verify nextPlanId is set
        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.nextPlanId, 2);
        assertEq(sub.planId, 3); // Current plan unchanged
    }

    function testCannotDowngradeToHigherTier() public {
        subscribeToBasicPlan();

        bytes memory intentSig = signDowngradeIntent(userPrivateKey, user, identity1, 3, 1);

        vm.prank(relayer);
        vm.expectRevert("VPN: not a downgrade");
        vpn.downgradeSubscription(user, identity1, 3, 1, intentSig);
    }

    // ============================================
    // Test: Cancel Pending Change
    // ============================================

    function testCancelPendingChange() public {
        subscribeToPremiumPlan();

        // Set pending downgrade
        bytes memory downgradeIntent = signDowngradeIntent(userPrivateKey, user, identity1, 2, 1);
        vm.prank(relayer);
        vpn.downgradeSubscription(user, identity1, 2, 1, downgradeIntent);

        // Cancel it (cancelNonces is separate from intentNonces, so use 0)
        bytes memory cancelIntent = signCancelChangeIntent(userPrivateKey, user, identity1, 0);
        vm.prank(relayer);
        vpn.cancelPendingChange(user, identity1, 0, cancelIntent);

        // Verify nextPlanId cleared
        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.nextPlanId, 0);
    }

    function testCannotCancelWhenNoPendingChange() public {
        subscribeToBasicPlan();

        bytes memory cancelIntent = signCancelChangeIntent(userPrivateKey, user, identity1, 1);

        vm.prank(relayer);
        vm.expectRevert("VPN: no pending change");
        vpn.cancelPendingChange(user, identity1, 1, cancelIntent);
    }

    // ============================================
    // Test: Apply Pending Change on Renewal
    // ============================================

    function testApplyPendingChangeOnRenewal() public {
        subscribeToPremiumPlan();

        // Set pending downgrade to Basic
        bytes memory downgradeIntent = signDowngradeIntent(userPrivateKey, user, identity1, 2, 1);
        vm.prank(relayer);
        vpn.downgradeSubscription(user, identity1, 2, 1, downgradeIntent);

        // Warp to expiration
        vm.warp(block.timestamp + 30 days);

        // Execute renewal
        vm.prank(relayer);
        vpn.executeRenewal(identity1);

        // Verify plan changed to Basic
        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.planId, 2);
        assertEq(sub.nextPlanId, 0); // Cleared after application
    }

    function testRenewalWithoutPendingChange() public {
        subscribeToBasicPlan();

        vm.warp(block.timestamp + 30 days);

        vm.prank(relayer);
        vpn.executeRenewal(identity1);

        // Verify plan unchanged
        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.planId, 2);
    }

    function testCannotExecuteRenewalTwiceWithinSameCycle() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 100000;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity1, 4, false, maxAmount, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity1, 4, false, maxAmount, deadline, 0, intentSig, v, r, s);

        vm.warp(block.timestamp + 1800);

        vm.prank(relayer);
        vpn.executeRenewal(identity1);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.nextRenewalAt, block.timestamp + 1800);
        assertEq(sub.renewedAt, block.timestamp);

        vm.warp(block.timestamp + 1);

        vm.prank(relayer);
        vm.expectRevert();
        vpn.executeRenewal(identity1);
    }

    function testRenewalWindowPassedPreventsLateCatchupCharges() public {
        subscribeToPremiumPlan();

        vm.warp(block.timestamp + 30 days + 3 days + 1);

        vm.prank(relayer);
        vm.expectRevert("VPN: renewal window passed");
        vpn.executeRenewal(identity1);
    }

    // ============================================
    // Test: Multi-Identity Support
    // ============================================

    function testMultipleIdentitiesPerUser() public {
        // Subscribe identity1 to Basic
        subscribeToBasicPlan();

        // Subscribe identity2 to Premium
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 10 * 1e6;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity2, 3, false, maxAmount, deadline, 1
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity2, 3, false, maxAmount, deadline, 1, intentSig, v, r, s);

        // Verify both subscriptions exist
        address[] memory identities = vpn.getUserIdentities(user);
        assertEq(identities.length, 2);
        assertEq(identities[0], identity1);
        assertEq(identities[1], identity2);

        // Verify different plans
        VPNSubscriptionV2.Subscription memory sub1 = vpn.getSubscription(identity1);
        VPNSubscriptionV2.Subscription memory sub2 = vpn.getSubscription(identity2);
        assertEq(sub1.planId, 2);
        assertEq(sub2.planId, 3);
    }

    // ============================================
    // Test: Edge Cases
    // ============================================

    function testBasicPlanChargesExpectedPrice() public {
        subscribeToBasicPlan();

        assertEq(usdc.balanceOf(serviceWallet), 5 * 1e6);
    }

    function testPremiumPlanHasUnlimitedTraffic() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 10 * 1e6;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity1, 3, false, maxAmount, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity1, 3, false, maxAmount, deadline, 0, intentSig, v, r, s);

        // Report huge traffic usage
        vm.prank(relayer);
        vpn.reportTrafficUsage(identity1, 1000 * 1024 * 1024 * 1024); // 1 TB

        // Should still be within limit
        (bool isWithinLimit,,) = vpn.checkTrafficLimit(identity1);
        assertTrue(isWithinLimit);
    }

    function testYearlySubscriptionHasCorrectPeriod() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAmount = 50 * 1e6;
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey, user, identity1, 2, true, maxAmount, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = signPermit(userPrivateKey, user, address(vpn), maxAmount, deadline);

        vm.prank(relayer);
        vpn.permitAndSubscribe(user, identity1, 2, true, maxAmount, deadline, 0, intentSig, v, r, s);

        VPNSubscriptionV2.Subscription memory sub = vpn.getSubscription(identity1);
        assertEq(sub.lockedPeriod, 365 days);
        assertEq(sub.expiresAt, block.timestamp + 365 days);
    }
}
