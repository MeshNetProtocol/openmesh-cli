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

        // 配置套餐 (合约构造函数已初始化三个套餐,这里可以选择性更新)
        // 套餐已在构造函数中初始化:
        // Plan 1: Free (0 USDC, 日限 100MB)
        // Plan 2: Basic (5 USDC/月, 50 USDC/年, 月限 100GB)
        // Plan 3: Premium (10 USDC/月, 100 USDC/年, 无限流量)
        console.log("Plans already initialized in constructor:");
        console.log("  Plan 1: Free (0 USDC, daily 100MB limit)");
        console.log("  Plan 2: Basic (5 USDC/month or 50 USDC/year, monthly 100GB limit)");
        console.log("  Plan 3: Premium (10 USDC/month or 100 USDC/year, unlimited)");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Contract:", address(vpn));
        console.log("Version: V2.1 (Three-tier subscription system)");
        console.log("\nPlans configured:");
        console.log("  1: Free (0 USDC, daily 100MB limit)");
        console.log("  2: Basic (5 USDC/month or 50 USDC/year, monthly 100GB limit)");
        console.log("  3: Premium (10 USDC/month or 100 USDC/year, unlimited)");
        console.log("\nNext steps:");
        console.log("1. Update .env: VPN_SUBSCRIPTION_CONTRACT=", address(vpn));
        console.log("2. Update CDP Paymaster whitelist with new contract address");
        console.log("3. Verify contract on Basescan");
    }
}
