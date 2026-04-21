# VPNCreditVaultV4 部署记录

## 最新部署信息（2026-04-21）

### 合约地址
- **VPNCreditVaultV4**: `0x92879A3a144b7894332ee2648E3BcB0616De6040`
- **USDC (Base Sepolia)**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

### 配置信息
- **Service Wallet**: `0x729e71ff357ccefAa31635931621531082A698f6`
- **Relayer**: `0x8c145d6ae710531A13952337Bf2e8A31916963F3`
- **Network**: Base Sepolia (Chain ID: 84532)

### 部署变更
本次部署修改了 `cancelAuthorization` 函数，使其支持 ERC-2612 permit 签名来减少 USDC allowance。

**修改前：**
```solidity
function cancelAuthorization(address identityAddress) external {
    address payer = identityToPayer[identityAddress];
    require(payer != address(0), "VPN: identity not bound");
    require(msg.sender == payer || msg.sender == relayer, "VPN: not authorized");
    authorizedAllowance[payer][identityAddress] = 0;
}
```

**修改后：**
```solidity
function cancelAuthorization(
    address user,
    address identityAddress,
    uint256 expectedAllowance,
    uint256 targetAllowance,
    uint256 deadline,
    uint8 v, bytes32 r, bytes32 s
) external onlyRelayer {
    require(identityToPayer[identityAddress] == user, "VPN: not identity owner");
    require(IERC20(address(usdc)).allowance(user, address(this)) == expectedAllowance, "VPN: allowance changed");
    
    uint256 toDeduct = expectedAllowance - targetAllowance;
    require(toDeduct == authorizedAllowance[user][identityAddress], "VPN: deduct amount mismatch");
    
    usdc.permit(user, address(this), targetAllowance, deadline, v, r, s);
    authorizedAllowance[user][identityAddress] = 0;
    
    emit ChargeAuthorized(user, identityAddress, expectedAllowance, targetAllowance);
}
```

### 设计对称性

| 操作 | 函数 | expectedAllowance | targetAllowance | USDC allowance 变化 | Vault authorizedAllowance 变化 |
|------|------|-------------------|-----------------|---------------------|--------------------------------|
| 订阅 | `authorizeChargeWithPermit` | 2.8 USDC | 6.4 USDC | +3.6 USDC | +3.6 USDC |
| 取消 | `cancelAuthorization` | 6.4 USDC | 2.8 USDC | -3.6 USDC | -3.6 USDC (清零) |

### CDP 配置更新

请在 CDP 配置中更新以下信息：
- Vault Contract Address: `0x92879A3a144b7894332ee2648E3BcB0616De6040`

### 后续工作

1. **后端修改**：更新订阅服务的取消订阅逻辑，调用新的 `cancelAuthorization` 函数
2. **前端修改**：让用户在取消订阅时签名 permit 来减少 USDC allowance
3. **测试验证**：测试完整的订阅-取消流程，确保 USDC allowance 和 Vault authorizedAllowance 同步

### 区块链浏览器
- Base Sepolia Explorer: https://sepolia.basescan.org/address/0x92879A3a144b7894332ee2648E3BcB0616De6040

---

## 历史部署记录

### 2026-04-19
- **VPNCreditVaultV4**: `0xD4b5DE7CA5Bfce22dd97ef059cAF100E4371a44d`
- 初始部署版本
