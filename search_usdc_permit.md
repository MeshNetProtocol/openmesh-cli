# USDC Permit 函数分析

根据 ERC-2612 标准，permit 函数的实现通常是：

```solidity
function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
) external {
    require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
    
    // 验证签名
    bytes32 digest = keccak256(
        abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
        )
    );
    
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNATURE");
    
    // 设置 allowance
    _approve(owner, spender, value);
}
```

关键点：
1. permit 函数会直接调用 `_approve(owner, spender, value)` 设置 allowance
2. **value 参数是目标 allowance 的绝对值，不是增量**
3. **permit 可以将 allowance 设置为任何值，包括 0**
4. **permit 可以将 allowance 从大值减少到小值**

但是，USDC 可能有自己的实现细节。让我检查一下是否有特殊限制。
