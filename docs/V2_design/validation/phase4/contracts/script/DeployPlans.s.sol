// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNSubscriptionV2.sol";

/**
 * @title DeployPlans
 * @notice 部署套餐配置脚本
 * @dev 在合约部署后执行，批量创建套餐
 *
 * 使用方法:
 * forge script script/DeployPlans.s.sol:DeployPlans \
 *   --rpc-url base-sepolia \
 *   --broadcast \
 *   --verify
 */
contract DeployPlans is Script {
    // 从环境变量读取合约地址
    address constant CONTRACT_ADDRESS = address(0); // 需要在运行时通过环境变量指定

    function run() external {
        // 从环境变量读取合约地址
        address contractAddr = vm.envAddress("VPN_SUBSCRIPTION_CONTRACT");
        require(contractAddr != address(0), "VPN_SUBSCRIPTION_CONTRACT not set");

        VPNSubscription vpn = VPNSubscription(contractAddr);

        // 从环境变量读取私钥（owner 账户）
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Plan 2: Basic Tier - 5 USDC/月
        vpn.setPlan(
            2,                          // planId
            "Basic",                    // name
            5 * 1e6,                    // pricePerMonth (5 USDC)
            50 * 1e6,                   // pricePerYear (50 USDC, 年付 8.3 折)
            30 days,                    // period
            1,                          // tier
            true                        // isActive
        );
        console.log("Plan 2 (Basic) created");

        // Plan 3: Premium Tier - 10 USDC/月
        vpn.setPlan(
            3,                          // planId
            "Premium",                  // name
            10 * 1e6,                   // pricePerMonth (10 USDC)
            100 * 1e6,                  // pricePerYear (100 USDC, 年付 8.3 折)
            30 days,                    // period
            2,                          // tier
            true                        // isActive
        );
        console.log("Plan 3 (Premium) created");

        // Plan 4: Test Low - 0.1 USDC / 30分钟
        vpn.setPlan(
            4,                          // planId
            "Test-Low",                 // name
            100000,                     // pricePerMonth (0.1 USDC)
            100000,                     // pricePerYear
            1800,                       // period (30 minutes)
            10,                         // tier
            true                        // isActive
        );
        console.log("Plan 4 (Test-Low) created");

        // Plan 5: Test Mid - 0.2 USDC / 30分钟
        vpn.setPlan(
            5,                          // planId
            "Test-Mid",                 // name
            200000,                     // pricePerMonth (0.2 USDC)
            200000,                     // pricePerYear
            1800,                       // period (30 minutes)
            11,                         // tier
            true                        // isActive
        );
        console.log("Plan 5 (Test-Mid) created");

        // Plan 6: Test High - 0.3 USDC / 30分钟
        vpn.setPlan(
            6,                          // planId
            "Test-High",                // name
            300000,                     // pricePerMonth (0.3 USDC)
            300000,                     // pricePerYear
            1800,                       // period (30 minutes)
            12,                         // tier
            true                        // isActive
        );
        console.log("Plan 6 (Test-High) created");

        vm.stopBroadcast();

        console.log("All plans deployed successfully!");
    }
}
