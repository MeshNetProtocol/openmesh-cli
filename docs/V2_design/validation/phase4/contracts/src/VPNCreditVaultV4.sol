// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title VPNCreditVaultV4
 * @notice 极简自动扣费合约，只负责绑定 identity 对应的 payer 并执行扣费
 * @dev 套餐、周期、到期时间、升级降级、取消订阅全部交给中心化服务端
 */
contract VPNCreditVaultV4 is Ownable, Pausable, ReentrancyGuard {
    IERC20Permit public immutable usdc;
    uint256 public constant USDC_UNIT = 1e6;

    address public serviceWallet;
    address public relayer;

    // identity -> payer 绑定关系
    mapping(address => address) public identityToPayer;

    event IdentityBound(address indexed payer, address indexed identity);

    event ChargeAuthorized(
        address indexed payer,
        address indexed identity,
        uint256 expectedAllowance,
        uint256 permitAmount
    );

    event IdentityCharged(
        address indexed payer,
        address indexed identity,
        uint256 amount
    );

    modifier onlyRelayer() {
        require(msg.sender == relayer, "VPN: not relayer");
        _;
    }

    constructor(
        address _usdc,
        address _serviceWallet,
        address _relayer
    ) Ownable(msg.sender) {
        usdc = IERC20Permit(_usdc);
        serviceWallet = _serviceWallet;
        relayer = _relayer;
    }

    function authorizeChargeWithPermit(
        address user,
        address identityAddress,
        uint256 expectedAllowance,
        uint256 permitAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRelayer whenNotPaused nonReentrant {
        require(identityAddress != address(0), "VPN: zero identity");
        require(permitAmount > 0, "VPN: zero permit");

        address boundPayer = identityToPayer[identityAddress];
        require(boundPayer == address(0) || boundPayer == user, "VPN: identity already bound");

        uint256 currentAllowance = IERC20(address(usdc)).allowance(user, address(this));
        require(currentAllowance == expectedAllowance, "VPN: allowance changed");
        require(permitAmount >= currentAllowance, "VPN: permit decreased");

        usdc.permit(user, address(this), permitAmount, deadline, v, r, s);

        if (boundPayer == address(0)) {
            identityToPayer[identityAddress] = user;
            emit IdentityBound(user, identityAddress);
        }

        emit ChargeAuthorized(user, identityAddress, expectedAllowance, permitAmount);
    }

    function charge(address identityAddress, uint256 amount)
        external
        onlyRelayer
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "VPN: zero amount");

        address payer = identityToPayer[identityAddress];
        require(payer != address(0), "VPN: identity not bound");

        require(
            IERC20(address(usdc)).transferFrom(payer, serviceWallet, amount),
            "VPN: transfer failed"
        );

        emit IdentityCharged(payer, identityAddress, amount);
    }

    function setRelayer(address _relayer) external onlyOwner {
        relayer = _relayer;
    }

    function setServiceWallet(address _serviceWallet) external onlyOwner {
        serviceWallet = _serviceWallet;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getIdentityPayer(address identityAddress) external view returns (address payer) {
        payer = identityToPayer[identityAddress];
    }
}
