// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title VPNCreditVaultV4
 * @notice 极简自动扣费合约，只负责绑定 identity 对应的 payer 并执行扣费
 * @dev 套餐、周期、到期时间、升级降级、取消订阅全部交给中心化服务端
 */
contract VPNCreditVaultV4 is Ownable {
    IERC20Permit public immutable usdc;
    uint256 public constant USDC_UNIT = 1e6;

    address public serviceWallet;
    address public relayer;

    // identity -> payer 绑定关系
    mapping(address => address) public identityToPayer;

    // (payer, identity) -> 已授权的 allowance 额度
    mapping(address => mapping(address => uint256)) public authorizedAllowance;

    // chargeId -> 是否已执行，用于防止同一笔扣费请求被重复扣费
    mapping(bytes32 => bool) public executedCharges;

    event IdentityBound(address indexed payer, address indexed identity);

    event ChargeAuthorized(
        address indexed payer,
        address indexed identity,
        uint256 expectedAllowance,
        uint256 targetAllowance
    );

    event IdentityCharged(
        bytes32 indexed chargeId,
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

    /**
     * @notice 使用 ERC-2612 permit 设置 payer 对本合约的 USDC allowance，并在首次授权时绑定 identity 到 payer
     * @dev
     * - `expectedAllowance` 是链下准备签名时观察到的当前 allowance
     * - `targetAllowance` 不是本次新增额度，而是本次 permit 执行后要设置的最终 allowance 总额
     * - 合约会先检查当前链上 allowance 必须等于 `expectedAllowance`，否则说明 allowance 在签名准备后发生了变化，交易会回滚
     * - 这样可以避免基于过期 allowance 快照提交 permit，导致最终 allowance 偏离调用方原本预期
     *
     * 例子：
     * - 当前 allowance = 100
     * - 希望额外增加 50
     * - 则应传入 `expectedAllowance = 100`，`targetAllowance = 150`
     * - 如果误传 `targetAllowance = 50`，表示要把 allowance 直接设置成 50，而不是在 100 的基础上增加 50
     */
    function authorizeChargeWithPermit(
        address user,
        address identityAddress,
        uint256 expectedAllowance,
        uint256 targetAllowance,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRelayer {
        require(identityAddress != address(0), "VPN: zero identity");
        require(targetAllowance > 0, "VPN: zero target allowance");

        // 验证 identity 绑定
        if (identityToPayer[identityAddress] != address(0)) {
            require(identityToPayer[identityAddress] == user, "VPN: identity already bound");
        }

        // 验证 allowance
        require(IERC20(address(usdc)).allowance(user, address(this)) == expectedAllowance, "VPN: allowance changed");
        require(targetAllowance >= expectedAllowance, "VPN: target allowance decreased");

        // 执行 permit
        usdc.permit(user, address(this), targetAllowance, deadline, v, r, s);

        // 绑定 identity（如果是首次）
        if (identityToPayer[identityAddress] == address(0)) {
            identityToPayer[identityAddress] = user;
            emit IdentityBound(user, identityAddress);
        }

        // 记录授权额度增量
        unchecked {
            authorizedAllowance[user][identityAddress] += (targetAllowance - expectedAllowance);
        }

        emit ChargeAuthorized(user, identityAddress, expectedAllowance, targetAllowance);
    }

    /**
     * @notice 按唯一 chargeId 执行一次扣费，并在链上做幂等去重
     * @dev
     * - `chargeId` 由中心化服务端生成并保证唯一，合约不关心它的业务编码规则
     * - 相同 `chargeId` 只能成功执行一次，避免多服务器并发或重试导致重复扣款
     * - chargeId 对应的订阅、套餐、账期、支付方式等业务细节由服务端维护和展示
     */
    function charge(bytes32 chargeId, address identityAddress, uint256 amount)
        external
        onlyRelayer
    {
        require(amount > 0, "VPN: zero amount");
        require(!executedCharges[chargeId], "VPN: charge already executed");
        require(identityToPayer[identityAddress] != address(0), "VPN: identity not bound");

        // 检查并扣减授权额度
        address payer = identityToPayer[identityAddress];
        require(authorizedAllowance[payer][identityAddress] >= amount, "VPN: insufficient authorized allowance");

        unchecked {
            authorizedAllowance[payer][identityAddress] -= amount;
        }

        executedCharges[chargeId] = true;

        require(
            IERC20(address(usdc)).transferFrom(payer, serviceWallet, amount),
            "VPN: transfer failed"
        );

        emit IdentityCharged(chargeId, payer, identityAddress, amount);
    }

    function setRelayer(address _relayer) external onlyOwner {
        relayer = _relayer;
    }

    function setServiceWallet(address _serviceWallet) external onlyOwner {
        serviceWallet = _serviceWallet;
    }

    function getIdentityPayer(address identityAddress) external view returns (address payer) {
        payer = identityToPayer[identityAddress];
    }

    function getAuthorizedAllowance(address payer, address identityAddress) external view returns (uint256) {
        return authorizedAllowance[payer][identityAddress];
    }

    /**
     * @notice 用户或 relayer 取消对某个 identity 的授权额度，防止后续自动扣费
     * @dev payer 本人或 relayer 都可以调用
     */
    function cancelAuthorization(address identityAddress) external {
        address payer = identityToPayer[identityAddress];
        require(payer != address(0), "VPN: identity not bound");
        require(msg.sender == payer || msg.sender == relayer, "VPN: not authorized");
        authorizedAllowance[payer][identityAddress] = 0;
    }
}
