// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VPNCreditVaultV4.sol";

/**
 * @title DeployPlansV3
 * @notice 已废弃
 * @dev V4 额度金库不再维护链上套餐，套餐与周期全部由中心化服务端管理
 */
contract DeployPlansV3 is Script {
    function run() external pure {
        revert("VPN: deprecated, V4 has no on-chain plans");
    }
}
