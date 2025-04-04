// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {PreDepositFactory} from "./PreDepositFactory.sol";

import {ShareReceiver} from "./ShareReceiver.sol";
import {IAccrossMessageReceiver} from "./interfaces/IAccrossMessageReceiver.sol";

contract DepositRelayer is IAccrossMessageReceiver {
    using SafeERC20 for ERC20;

    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 originChainId
    );

    modifier onlyGovernance() {
        require(
            msg.sender == PreDepositFactory(PRE_DEPOSIT_FACTORY).governance(),
            "!governance"
        );
        _;
    }

    /// @notice Address of the Across bridge
    address public immutable ACROSS_BRIDGE;

    /// @notice Address to hold the vault shares
    address public immutable SHARE_RECEIVER;

    /// @notice Address of the factory that deployed this contract
    address public immutable PRE_DEPOSIT_FACTORY;

    constructor(address _acrossBridge) {
        PRE_DEPOSIT_FACTORY = msg.sender;
        require(_acrossBridge != address(0), "ZERO_ADDRESS");
        ACROSS_BRIDGE = _acrossBridge;
        SHARE_RECEIVER = address(new ShareReceiver(msg.sender));
    }

    /// @notice function called by Across bridge when funds arrive
    function handleV3AcrossMessage(
        address token,
        uint256 amount,
        address /* relayer */,
        bytes memory message
    ) external {
        require(msg.sender == ACROSS_BRIDGE, "Invalid caller");
        address vault = PreDepositFactory(PRE_DEPOSIT_FACTORY).preDepositVault(
            token
        );
        require(vault != address(0), "Vault not set");

        // Funds should have been transferred to this contract before calling this function
        require(
            amount > 0 && ERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient amount"
        );

        (address user, uint256 originChainId) = abi.decode(
            message,
            (address, uint256)
        );
        require(user != address(0), "Invalid user");
        require(originChainId != 0, "Invalid chain id");

        _deposit(token, vault, user, amount, originChainId);
    }

    function _deposit(
        address token,
        address vault,
        address user,
        uint256 amount,
        uint256 originChainId
    ) internal {
        // Approve vault to spend tokens
        ERC20(token).forceApprove(address(vault), amount);

        // Deposit into vault and send shares to recipient
        IVault(vault).deposit(amount, SHARE_RECEIVER);

        // TODO: Should this be in shares in case PPS increases?
        ShareReceiver(SHARE_RECEIVER).depositProcessed(token, user, amount);

        emit DepositProcessed(token, user, amount, originChainId);
    }

    /// @notice Deposit tokens into the vault
    /// @dev This is ued by those on the same chain.
    function deposit(address token, uint256 amount) external {
        address vault = PreDepositFactory(PRE_DEPOSIT_FACTORY).preDepositVault(
            token
        );
        require(vault != address(0), "Vault not set");
        require(amount > 0, "Invalid amount");

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, vault, msg.sender, amount, block.chainid);
    }

    function rescue(address token) external onlyGovernance {
        ERC20(token).safeTransfer(
            msg.sender,
            ERC20(token).balanceOf(address(this))
        );
    }
}
