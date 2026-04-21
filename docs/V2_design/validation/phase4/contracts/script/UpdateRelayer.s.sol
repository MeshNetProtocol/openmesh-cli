// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNCreditVaultV4.sol";

contract UpdateRelayerScript is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_CONTRACT_ADDRESS");
        address newRelayer = vm.envAddress("NEW_RELAYER_ADDRESS");
        
        vm.startBroadcast();
        
        VPNCreditVaultV4 vault = VPNCreditVaultV4(vaultAddress);
        vault.setRelayer(newRelayer);
        
        console.log("Relayer updated to:", newRelayer);
        
        vm.stopBroadcast();
    }
}
