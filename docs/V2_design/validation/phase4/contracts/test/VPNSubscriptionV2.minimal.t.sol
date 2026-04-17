// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VPNSubscriptionV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 最小化测试文件 - 只测试核心功能，不测试已删除的函数
contract VPNSubscriptionV2MinimalTest is Test {
    VPNSubscription public vpn;
    ERC20 public usdc;
    
    address public owner = address(this);
    address public relayer = address(0x1);
    address public serviceWallet = address(0x2);
    
    function setUp() public {
        // 部署 mock USDC
        usdc = new MockUSDC();
        
        // 部署 VPN 合约
        vpn = new VPNSubscription(address(usdc), serviceWallet, relayer);
    }
    
    function testBasicSetup() public view {
        assertEq(address(vpn.usdc()), address(usdc));
        assertEq(vpn.serviceWallet(), serviceWallet);
        assertEq(vpn.relayer(), relayer);
    }
}

// Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
