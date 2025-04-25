// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {ShareReceiver} from "./ShareReceiver.sol";
import {PreDepositFactory} from "./PreDepositFactory.sol";
import {IAccrossMessageReceiver} from "./interfaces/IAccrossMessageReceiver.sol";

contract DepositRelayer is Governance2Step, IAccrossMessageReceiver {
    using SafeERC20 for ERC20;

    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 originChainId,
        address referral
    );

    /// @notice Event emitted when a vault is set for a specific asset
    event VaultSet(address indexed asset, address indexed vault);

    /// @notice Event emitted when a deposit cap is set for a specific asset
    event DepositCapSet(address indexed asset, uint256 indexed cap);

    modifier onlyVaultFactory() {
        require(msg.sender == PRE_DEPOSIT_FACTORY, "!vaultFactory");
        _;
    }

    /// @notice Address of the WETH token
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Address of the Across bridge
    address public immutable ACROSS_BRIDGE;

    /// @notice Address of the RelayLink bridge
    address public immutable RELAY_LINK_BRIDGE;

    /// @notice Address to hold the vault shares
    address public immutable SHARE_RECEIVER;

    /// @notice Address of the factory that deployed this contract
    address public immutable PRE_DEPOSIT_FACTORY;

    /// @notice Token to stb depositor strategy for any deployed vaults
    mapping(address => address) public stbDepositor;

    /// @notice Token to vault mapping for any deployed vaults
    mapping(address => address) public preDepositVault;

    /// @notice Track deposit cap for each token
    mapping(address => uint256) public depositCap;

    /// @notice Track total deposited amount for each token
    /// Track token instead of vault incase vault is updated
    mapping(address => uint256) public totalDeposited;

    /// @notice Track deposited amount for each token and user
    /// @dev Use token instead of vault incase vault is updated
    mapping(address => mapping(address => uint256)) public deposited;

    constructor(
        address _governance,
        address _acrossBridge,
        address _relayLinkBridge
    ) Governance2Step(_governance) {
        PRE_DEPOSIT_FACTORY = msg.sender;
        require(_acrossBridge != address(0), "ZERO_ADDRESS");
        require(_relayLinkBridge != address(0), "ZERO_ADDRESS");
        ACROSS_BRIDGE = _acrossBridge;
        RELAY_LINK_BRIDGE = _relayLinkBridge;
        SHARE_RECEIVER = address(new ShareReceiver());
    }

    /// @notice function called by Across bridge when funds arrive
    function handleV3AcrossMessage(
        address token,
        uint256 amount,
        address /* relayer */,
        bytes memory message
    ) external {
        require(msg.sender == ACROSS_BRIDGE, "Invalid caller");
        (address user, uint256 originChainId, address referral) = abi.decode(
            message,
            (address, uint256, address)
        );

        _handleBridgeDeposit(token, amount, user, originChainId, referral);
    }

    /// @notice function called by RelayLink bridge when funds arrive
    function handleRelayLinkDeposit(
        address token,
        uint256 amount,
        address user,
        uint256 originChainId,
        address referral
    ) external {
        require(msg.sender == RELAY_LINK_BRIDGE, "Invalid caller");
        _handleBridgeDeposit(token, amount, user, originChainId, referral);
    }

    function _handleBridgeDeposit(
        address token,
        uint256 amount,
        address user,
        uint256 originChainId,
        address referral
    ) internal {
        address vault = preDepositVault[token];
        require(vault != address(0), "Vault not set");

        // Funds should have been transferred to this contract before calling this function
        require(
            amount > 0 && ERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient amount"
        );

        require(user != address(0), "Invalid user");
        require(originChainId != 0, "Invalid chain id");

        _deposit(token, vault, user, amount, originChainId, referral);
    }

    function _deposit(
        address token,
        address vault,
        address user,
        uint256 amount,
        uint256 originChainId,
        address referral
    ) internal {
        require(amount <= maxDeposit(token), "Deposit cap exceeded");

        // Approve vault to spend tokens
        ERC20(token).forceApprove(address(vault), amount);

        // Deposit into vault and send shares to recipient
        IVault(vault).deposit(amount, SHARE_RECEIVER);

        // Record deposit
        deposited[token][user] += amount;
        totalDeposited[token] += amount;

        emit DepositProcessed(token, user, amount, originChainId, referral);
    }

    /// @notice Deposit tokens into the vault
    /// @dev This is ued by those on the same chain and default to no referral
    function deposit(address token, uint256 amount) public {
        deposit(token, amount, address(0));
    }

    /// @notice Deposit tokens into the vault
    /// @dev This is ued by those on the same chain.
    function deposit(address token, uint256 amount, address referral) public {
        address vault = preDepositVault[token];
        require(vault != address(0), "Vault not set");
        require(amount > 0, "Invalid amount");

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, vault, msg.sender, amount, block.chainid, referral);
    }

    /// @notice Deposit ETH into the vault
    /// @dev This is used by those on the same chain and default to no referral
    function depositEth() public payable {
        depositEth(address(0));
    }

    /// @notice Deposit ETH into the vault
    /// @dev This is used by those on the same chain.
    function depositEth(address referral) public payable {
        address vault = preDepositVault[WETH];
        require(vault != address(0), "Vault not set");
        uint256 amount = msg.value;
        require(amount > 0, "Invalid amount");
        IWETH(WETH).deposit{value: amount}();

        _deposit(WETH, vault, msg.sender, amount, block.chainid, referral);
    }

    /// @notice Get the max deposit amount for a specific token
    /// @param token The token address
    /// @return The max deposit amount
    function maxDeposit(address token) public view returns (uint256) {
        uint256 cap = depositCap[token];
        if (cap == type(uint256).max) {
            return cap;
        }

        uint256 totalDeposits = totalDeposited[token];
        if (totalDeposits >= cap) {
            return 0;
        }

        return cap - totalDeposits;
    }

    /// @notice Sets the deposit cap for a specific asset
    /// @dev Can only be called by the governance
    /// @param token The token address
    /// @param cap The new deposit cap
    function setDepositCap(address token, uint256 cap) external onlyGovernance {
        depositCap[token] = cap;
        emit DepositCapSet(token, cap);
    }

    /// @notice Sets the vault for a specific asset
    /// @dev Can only be called by the governance to override the vault
    /// @param asset The token address
    /// @param vault The corresponding Pre-Deposit vault address
    function setVault(address asset, address vault) external onlyGovernance {
        require(asset != address(0), "ZERO_ADDRESS");

        preDepositVault[asset] = vault;
        emit VaultSet(asset, vault);
    }

    /// @notice Notify relayer of new vault
    /// @dev Can only be called by the vault factory
    /// @param token The token address
    /// @param vault The corresponding Pre-Deposit vault address
    /// @param stbStrategy The corresponding STB depositor strategy address
    function newVault(
        address token,
        address vault,
        address stbStrategy
    ) external onlyVaultFactory {
        require(token != address(0), "ZERO_ADDRESS");

        preDepositVault[token] = vault;
        stbDepositor[token] = stbStrategy;
        depositCap[token] = type(uint256).max;
    }

    function rescue(address token) external onlyGovernance {
        ERC20(token).safeTransfer(
            msg.sender,
            ERC20(token).balanceOf(address(this))
        );
    }
}
