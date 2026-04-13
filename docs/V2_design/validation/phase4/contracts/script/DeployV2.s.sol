// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNSubscriptionV2.sol";

/**
 * @title Deploy VPNSubscription V2
 * @notice 部署支持多订阅的 VPN 订阅合约（包含测试套餐）
 */
contract DeployV2Script is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address serviceWallet = vm.envAddress("SERVICE_WALLET_ADDRESS");
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        address usdc = vm.envAddress("USDC_CONTRACT");

        console.log("=== Deploying VPNSubscription V2 ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Service Wallet:", serviceWallet);
        console.log("Relayer:", relayer);
        console.log("USDC:", usdc);

        vm.startBroadcast(deployerPrivateKey);

        // 部署合约
        VPNSubscription vpn = new VPNSubscription(usdc, serviceWallet, relayer);
        console.log("\nVPNSubscription V2 deployed at:", address(vpn));

        // 配置套餐
        // Plan 1: 月付套餐 - 5 USDC / 30 天
        vpn.setPlan(1, 5_000000, 30 days, true);
        console.log("Plan 1 (Monthly) configured: 5 USDC / 30 days");

        // Plan 2: 年付套餐 - 50 USDC / 365 天
        vpn.setPlan(2, 50_000000, 365 days, true);
        console.log("Plan 2 (Yearly) configured: 50 USDC / 365 days");

        // ⚠️ Plan 3: 测试套餐 - 0.1 USDC / 30 分钟（仅测试网）
        vpn.setPlan(3, 100000, 30 minutes, true);
        console.log("Plan 3 (Test) configured: 0.1 USDC / 30 minutes [TESTNET ONLY]");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Contract:", address(vpn));
        console.log("Version: V2 (Multi-subscription support)");
        console.log("\nPlans configured:");
        console.log("  1: Monthly (5 USDC / 30 days)");
        console.log("  2: Yearly (50 USDC / 365 days)");
        console.log("  3: Test (0.1 USDC / 30 min) - TESTNET ONLY");
        console.log("\nNext steps:");
        console.log("1. Update .env: VPN_SUBSCRIPTION_CONTRACT=", address(vpn));
        console.log("2. Update CDP Paymaster whitelist with new contract address");
        console.log("3. Verify contract on Basescan");
    }
}
