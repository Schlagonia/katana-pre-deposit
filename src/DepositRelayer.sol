// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {IAccrossMessageReceiver} from "./interfaces/IAccrossMessageReceiver.sol";

contract DepositRelayer is Governance2Step, IAccrossMessageReceiver {
    using SafeERC20 for ERC20;

    event VaultSet(address indexed asset, address indexed vault);
    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount
    );

    error ZERO_ADDRESS();
    error InvalidAsset();
    error InvalidCaller();
    error InsufficientAmount();

    modifier onlyPreDepositFactory() {
        if (msg.sender != PRE_DEPOSIT_FACTORY && msg.sender != governance)
            revert InvalidCaller();
        _;
    }

    /// @notice Address of the Across bridge
    address public immutable ACROSS_BRIDGE;

    /// @notice Address to hold the vault shares
    address public immutable SHARE_RECEIVER;

    /// @notice Address of the factory that deployed this contract
    address public immutable PRE_DEPOSIT_FACTORY;

    /// @notice Track vault for each asset. Should be set by factory.
    mapping(address => address) public assetToVault;

    /// @notice Track deposited amount for each token and user
    /// @dev Use token instead of vault incase vault is updated
    mapping(address => mapping(address => uint256)) public deposited;

    constructor(
        address _governance,
        address _acrossBridge,
        address _shareReceiver
    ) Governance2Step(_governance) {
        PRE_DEPOSIT_FACTORY = msg.sender;
        if (_acrossBridge == address(0)) revert ZERO_ADDRESS();
        ACROSS_BRIDGE = _acrossBridge;
        SHARE_RECEIVER = _shareReceiver;
    }

    /// @notice Sets the vault for a specific asset
    /// @param asset The token address
    /// @param vault The corresponding Yearn vault address
    function setVault(
        address asset,
        address vault
    ) external onlyPreDepositFactory {
        if (asset == address(0)) revert ZERO_ADDRESS();

        assetToVault[asset] = vault;
        emit VaultSet(asset, vault);
    }

    /// @notice function called by Across bridge when funds arrive
    function handleV3AcrossMessage(
        address token,
        uint256 amount,
        address /* relayer */,
        bytes memory message
    ) external {
        if (msg.sender != ACROSS_BRIDGE) revert InvalidCaller();

        // Funds should have been transferred to this contract before calling this function
        if (amount == 0 || ERC20(token).balanceOf(address(this)) < amount)
            revert InsufficientAmount();

        address user = abi.decode(message, (address));
        require(user != address(0), "Invalid user");

        _deposit(token, user, amount);
    }

    function _deposit(address token, address user, uint256 amount) internal {
        address vault = assetToVault[token];
        if (vault == address(0)) revert InvalidAsset();

        // Approve vault to spend tokens
        ERC20(token).forceApprove(address(vault), amount);

        // Deposit into vault and send shares to recipient
        IVault(vault).deposit(amount, SHARE_RECEIVER);

        // Update deposited amount for tracking
        deposited[token][user] += amount;

        emit DepositProcessed(token, user, amount);
    }

    /// @notice Deposit tokens into the vault
    /// @dev This is ued by those on the same chain.
    function deposit(address token, uint256 amount) external {
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, msg.sender, amount);
    }
}
