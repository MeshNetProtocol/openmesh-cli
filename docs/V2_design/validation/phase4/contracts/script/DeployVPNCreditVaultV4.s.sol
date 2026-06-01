// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNCreditVaultV4.sol";

contract DeployVPNCreditVaultV4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdc = vm.envAddress("USDC_CONTRACT");
        address serviceWallet = vm.envAddress("SERVICE_WALLET_ADDRESS");
        address relayer = vm.envAddress("RELAYER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        VPNCreditVaultV4 vault = new VPNCreditVaultV4(
            usdc,
            serviceWallet,
            relayer
        );

        console.log("VPNCreditVaultV4 deployed at:", address(vault));
        console.log("USDC:", usdc);
        console.log("Service Wallet:", serviceWallet);
        console.log("Relayer:", relayer);

        vm.stopBroadcast();
    }
}
