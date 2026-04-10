// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VPNSubscription.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

contract VPNSubscriptionTest is Test {
    VPNSubscription public vpn;
    MockUSDC public usdc;

    address public owner;
    address public relayer;
    address public serviceWallet;
    address public user;
    address public identityAddress;

    uint256 public userPrivateKey;
    uint256 public relayerPrivateKey;

    // EIP-712 domain separator
    bytes32 public DOMAIN_SEPARATOR;

    function setUp() public {
        owner = address(this);
        relayer = vm.addr(1);
        serviceWallet = vm.addr(2);
        userPrivateKey = 0x1234;
        user = vm.addr(userPrivateKey);
        identityAddress = vm.addr(3);

        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy VPN contract
        vpn = new VPNSubscription(address(usdc), serviceWallet, relayer);

        // Compute domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VPNSubscription")),
                keccak256(bytes("1")),
                block.chainid,
                address(vpn)
            )
        );

        // Mint USDC to user
        usdc.mint(user, 1000 * 1e6); // 1000 USDC
    }

    // Helper: Sign SubscribeIntent
    function signSubscribeIntent(
        uint256 privateKey,
        address _user,
        address _identity,
        uint256 planId,
        uint256 maxAmount,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("SubscribeIntent(address user,address identityAddress,uint256 planId,uint256 maxAmount,uint256 deadline,uint256 nonce)"),
                _user,
                _identity,
                planId,
                maxAmount,
                deadline,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Helper: Sign CancelIntent
    function signCancelIntent(
        uint256 privateKey,
        address _user,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("CancelIntent(address user,uint256 nonce)"),
                _user,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Helper: Sign permit
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

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash)
        );

        return vm.sign(privateKey, digest);
    }

    // ============================================
    // Test: Basic subscription flow
    // ============================================

    function testPermitAndSubscribe() public {
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6; // 12 months
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        // Sign SubscribeIntent
        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        // Sign permit
        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        uint256 balanceBefore = usdc.balanceOf(serviceWallet);

        // Execute subscription as relayer
        vm.prank(relayer);
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );

        // Verify subscription created
        (
            address storedIdentity,
            uint96 lockedPrice,
            uint256 storedPlanId,
            uint256 lockedPeriod,
            uint256 startTime,
            uint256 expiresAt,
            bool autoRenewEnabled,
            bool isActive
        ) = vpn.subscriptions(user);

        assertEq(storedIdentity, identityAddress);
        assertEq(lockedPrice, 5 * 1e6);
        assertEq(storedPlanId, planId);
        assertEq(lockedPeriod, 30 days);
        assertEq(startTime, block.timestamp);
        assertEq(expiresAt, block.timestamp + 30 days);
        assertTrue(autoRenewEnabled);
        assertTrue(isActive);

        // Verify payment
        assertEq(usdc.balanceOf(serviceWallet), balanceBefore + 5 * 1e6);

        // Verify identity binding
        assertEq(vpn.identityToOwner(identityAddress), user);

        // Verify nonce incremented
        assertEq(vpn.intentNonces(user), 1);
    }

    function testCannotSubscribeTwice() public {
        // First subscription
        testPermitAndSubscribe();

        // Try to subscribe again
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 1;

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            vm.addr(4), // different identity
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: already subscribed");
        vpn.permitAndSubscribe(
            user,
            vm.addr(4),
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    function testCannotBindSameIdentityTwice() public {
        testPermitAndSubscribe();

        // Try to subscribe with same identity from different user
        address user2 = vm.addr(0x5678);
        uint256 user2PrivateKey = 0x5678;
        usdc.mint(user2, 100 * 1e6);

        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        bytes memory intentSig = signSubscribeIntent(
            user2PrivateKey,
            user2,
            identityAddress, // same identity
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            user2PrivateKey,
            user2,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: identity already bound");
        vpn.permitAndSubscribe(
            user2,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    // ============================================
    // Test: EIP-712 signature verification
    // ============================================

    function testInvalidIntentSignature() public {
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        // Sign with wrong private key
        bytes memory intentSig = signSubscribeIntent(
            0x9999, // wrong key
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: invalid intent signature");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    function testIntentNonceReplay() public {
        testPermitAndSubscribe();

        // Cancel subscription to allow resubscribe
        vm.prank(user);
        vpn.cancelSubscription();

        vm.warp(block.timestamp + 31 days);

        vm.prank(relayer);
        vpn.finalizeExpired(user, false);

        // Try to replay old signature with nonce 0
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0; // old nonce

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: invalid intent nonce");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    // ============================================
    // Test: Renewal
    // ============================================

    function testExecuteRenewal() public {
        testPermitAndSubscribe();

        // Get original expiration time
        (, , , , , uint256 originalExpiresAt, , ) = vpn.subscriptions(user);

        // Warp to expiration
        vm.warp(originalExpiresAt);

        uint256 balanceBefore = usdc.balanceOf(serviceWallet);

        // Execute renewal
        vm.prank(relayer);
        vpn.executeRenewal(user);

        // Verify payment
        assertEq(usdc.balanceOf(serviceWallet), balanceBefore + 5 * 1e6);

        // Verify expiration extended (should be originalExpiresAt + 30 days)
        (, , , , , uint256 newExpiresAt, , ) = vpn.subscriptions(user);
        assertEq(newExpiresAt, originalExpiresAt + 30 days);
    }

    function testCannotRenewBeforeExpiration() public {
        testPermitAndSubscribe();

        // Try to renew before expiration
        vm.prank(relayer);
        vm.expectRevert("VPN: not yet expired");
        vpn.executeRenewal(user);
    }

    function testRenewalFailsWithInsufficientBalance() public {
        testPermitAndSubscribe();

        // Get original expiration time
        (, , , , , uint256 originalExpiresAt, , ) = vpn.subscriptions(user);

        // Remove user's USDC by burning it
        uint256 userBalance = usdc.balanceOf(user);
        vm.prank(user);
        usdc.transfer(address(1), userBalance); // burn to address(1)

        // Warp to expiration
        vm.warp(originalExpiresAt);

        // Try to renew - should emit RenewalFailed
        vm.prank(relayer);
        vm.expectEmit(true, false, false, true);
        emit VPNSubscription.RenewalFailed(user, "insufficient balance");
        vpn.executeRenewal(user);
    }

    function testRenewalUsesLockedPrice() public {
        testPermitAndSubscribe();

        // Change plan price
        vpn.setPlan(1, 10 * 1e6, 30 days, true);

        // Warp to expiration
        vm.warp(block.timestamp + 30 days);

        uint256 balanceBefore = usdc.balanceOf(serviceWallet);

        // Execute renewal - should use old price (5 USDC)
        vm.prank(relayer);
        vpn.executeRenewal(user);

        assertEq(usdc.balanceOf(serviceWallet), balanceBefore + 5 * 1e6);
    }

    // ============================================
    // Test: Cancel subscription
    // ============================================

    function testCancelSubscription() public {
        testPermitAndSubscribe();

        // Cancel
        vm.prank(user);
        vpn.cancelSubscription();

        // Verify autoRenewEnabled is false
        (, , , , , , bool autoRenewEnabled, bool isActive) = vpn.subscriptions(user);
        assertFalse(autoRenewEnabled);
        assertTrue(isActive); // still active until expiration
    }

    function testCancelFor() public {
        testPermitAndSubscribe();

        uint256 nonce = 0;
        bytes memory sig = signCancelIntent(userPrivateKey, user, nonce);

        // Cancel via relayer
        vm.prank(relayer);
        vpn.cancelFor(user, nonce, sig);

        // Verify
        (, , , , , , bool autoRenewEnabled, bool isActive) = vpn.subscriptions(user);
        assertFalse(autoRenewEnabled);
        assertTrue(isActive);

        // Verify nonce incremented
        assertEq(vpn.cancelNonces(user), 1);
    }

    function testCannotCancelTwice() public {
        testCancelSubscription();

        vm.prank(user);
        vm.expectRevert("VPN: already cancelled");
        vpn.cancelSubscription();
    }

    // ============================================
    // Test: Finalize expired
    // ============================================

    function testFinalizeExpiredNatural() public {
        testPermitAndSubscribe();

        // Cancel subscription
        vm.prank(user);
        vpn.cancelSubscription();

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Finalize
        vm.prank(relayer);
        vpn.finalizeExpired(user, false);

        // Verify subscription is inactive
        (, , , , , , , bool isActive) = vpn.subscriptions(user);
        assertFalse(isActive);

        // Verify identity released
        assertEq(vpn.identityToOwner(identityAddress), address(0));
    }

    function testFinalizeExpiredForced() public {
        testPermitAndSubscribe();

        // Force close (e.g., after 3 failed renewals)
        vm.prank(relayer);
        vpn.finalizeExpired(user, true);

        // Verify subscription is inactive
        (, , , , , , bool autoRenewEnabled, bool isActive) = vpn.subscriptions(user);
        assertFalse(autoRenewEnabled);
        assertFalse(isActive);

        // Verify identity released
        assertEq(vpn.identityToOwner(identityAddress), address(0));
    }

    function testCannotFinalizeNaturalWithAutoRenewOn() public {
        testPermitAndSubscribe();

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Try to finalize without canceling first
        vm.prank(relayer);
        vm.expectRevert("VPN: auto renew still on");
        vpn.finalizeExpired(user, false);
    }

    function testCanResubscribeAfterFinalize() public {
        testFinalizeExpiredNatural();

        // User can now resubscribe with same identity
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 1; // nonce incremented

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress, // same identity
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );

        // Verify new subscription
        (, , , , , , , bool isActive) = vpn.subscriptions(user);
        assertTrue(isActive);
    }

    // ============================================
    // Test: Access control
    // ============================================

    function testOnlyRelayerCanCallPermitAndSubscribe() public {
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        // Try to call as non-relayer
        vm.prank(user);
        vm.expectRevert("VPN: not relayer");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    function testOnlyOwnerCanSetPlan() public {
        vm.prank(user);
        vm.expectRevert();
        vpn.setPlan(3, 15 * 1e6, 90 days, true);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        vpn.pause();
    }

    // ============================================
    // Test: Edge cases
    // ============================================

    function testMaxAmountTooLow() public {
        uint256 planId = 1;
        uint256 maxAmount = 1 * 1e6; // less than plan price
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: maxAmount too low");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    function testPermitExpired() public {
        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp - 1; // expired
        uint256 intentNonce = 0;

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: permit expired");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }

    function testInactivePlan() public {
        // Deactivate plan
        vpn.setPlan(1, 5 * 1e6, 30 days, false);

        uint256 planId = 1;
        uint256 maxAmount = 60 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 intentNonce = 0;

        bytes memory intentSig = signSubscribeIntent(
            userPrivateKey,
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce
        );

        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            userPrivateKey,
            user,
            address(vpn),
            maxAmount,
            deadline
        );

        vm.prank(relayer);
        vm.expectRevert("VPN: plan not available");
        vpn.permitAndSubscribe(
            user,
            identityAddress,
            planId,
            maxAmount,
            deadline,
            intentNonce,
            intentSig,
            v, r, s
        );
    }
}
