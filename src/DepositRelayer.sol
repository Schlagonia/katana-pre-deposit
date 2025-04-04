// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {Accountant} from "./Accountant.sol";
import {ShareReceiver} from "./ShareReceiver.sol";
import {IAccrossMessageReceiver} from "./interfaces/IAccrossMessageReceiver.sol";

contract DepositRelayer is Governance2Step, IAccrossMessageReceiver {
    using SafeERC20 for ERC20;

    event VaultSet(address indexed asset, address indexed vault);
    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 originChainId
    );

    modifier onlyPreDepositFactory() {
        require(
            msg.sender == PRE_DEPOSIT_FACTORY || msg.sender == governance,
            "Invalid caller"
        );
        _;
    }

    /// @notice Address of the Across bridge
    address public immutable ACROSS_BRIDGE;

    /// @notice Address of the accountant
    address public immutable ACCOUNTANT;

    /// @notice Address to hold the vault shares
    address public immutable SHARE_RECEIVER;

    /// @notice Address of the factory that deployed this contract
    address public immutable PRE_DEPOSIT_FACTORY;

    /// @notice Track vault for each asset. Should be set by factory.
    mapping(address => address) public assetToVault;

    constructor(
        address _governance,
        address _acrossBridge
    ) Governance2Step(_governance) {
        PRE_DEPOSIT_FACTORY = msg.sender;
        require(_acrossBridge != address(0), "ZERO_ADDRESS");
        ACROSS_BRIDGE = _acrossBridge;
        SHARE_RECEIVER = address(new ShareReceiver());
        ACCOUNTANT = address(new Accountant());
    }

    /// @notice Sets the vault for a specific asset
    /// @param asset The token address
    /// @param vault The corresponding Yearn vault address
    function setVault(
        address asset,
        address vault
    ) external onlyPreDepositFactory {
        require(asset != address(0), "ZERO_ADDRESS");

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
        require(msg.sender == ACROSS_BRIDGE, "Invalid caller");

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

        _deposit(token, user, amount, originChainId);
    }

    function _deposit(
        address token,
        address user,
        uint256 amount,
        uint256 originChainId
    ) internal {
        address vault = assetToVault[token];
        require(vault != address(0), "Invalid asset");

        // Approve vault to spend tokens
        ERC20(token).forceApprove(address(vault), amount);

        // Deposit into vault and send shares to recipient
        IVault(vault).deposit(amount, SHARE_RECEIVER);

        ShareReceiver(SHARE_RECEIVER).depositProcessed(token, user, amount);

        emit DepositProcessed(token, user, amount, originChainId);
    }

    /// @notice Deposit tokens into the vault
    /// @dev This is ued by those on the same chain.
    function deposit(address token, uint256 amount) external {
        require(assetToVault[token] != address(0), "Vault not set");
        require(amount > 0, "Invalid amount");

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, msg.sender, amount, block.chainid);
    }

    function rescue(address token) external onlyGovernance {
        ERC20(token).safeTransfer(
            msg.sender,
            ERC20(token).balanceOf(address(this))
        );
    }
}
