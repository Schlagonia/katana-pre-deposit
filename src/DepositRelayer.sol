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
        uint256 amount,
        uint256 shares,
        bool mintLootBox
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

    address public immutable ACROSS_BRIDGE;

    address public immutable SHARE_RECEIVER;

    address public immutable PRE_DEPOSIT_FACTORY;

    mapping(address => address) public assetToVault;

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
        if (amount == 0 || ERC20(token).balanceOf(address(this)) < amount)
            revert InsufficientAmount();
        bool mintLootBox = abi.decode(message, (bool));
        _deposit(token, amount, mintLootBox);
    }

    function _deposit(
        address token,
        uint256 amount,
        bool mintLootBox
    ) internal {
        address vault = assetToVault[token];
        if (vault == address(0)) revert InvalidAsset();

        if (mintLootBox) {
            // TODO: Mint loot box
        }

        // Approve vault to spend tokens
        ERC20(token).forceApprove(address(vault), amount);

        // Deposit into vault and send shares to recipient
        uint256 shares = IVault(vault).deposit(amount, SHARE_RECEIVER);

        emit DepositProcessed(token, amount, shares, mintLootBox);
    }

    // Limit the recipient of the shares?
    function deposit(address token, uint256 amount, bool mintLootBox) external {
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, amount, mintLootBox);
    }
}
