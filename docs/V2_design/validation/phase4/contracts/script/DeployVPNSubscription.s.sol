// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNSubscription.sol";

contract DeployVPNSubscription is Script {
    function run() external {
        // Base Sepolia USDC address
        address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        // Read from environment variables
        address serviceWallet = vm.envAddress("SERVICE_WALLET_ADDRESS");
        address relayer = vm.envAddress("RELAYER_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        VPNSubscription vpn = new VPNSubscription(
            usdc,
            serviceWallet,
            relayer
        );

        vm.stopBroadcast();

        console.log("VPNSubscription deployed to:", address(vpn));
        console.log("USDC:", usdc);
        console.log("Service Wallet:", serviceWallet);
        console.log("Relayer:", relayer);
    }
}
