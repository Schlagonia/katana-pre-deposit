// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {ShareReceiver} from "./ShareReceiver.sol";
import {IAcrossMessageReceiver} from "./interfaces/IAcrossMessageReceiver.sol";

contract DepositRelayer is Governance2Step, IAcrossMessageReceiver {
    using SafeERC20 for ERC20;

    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 originChainId,
        address referral
    );

    /// @notice Event emitted when the Across bridge is set
    event AcrossBridgeSet(address indexed acrossBridge);

    /// @notice Event emitted when the RelayLink bridge is set
    event RelayLinkBridgeSet(address indexed relayLinkBridge);

    /// @notice Event emitted when a vault is set for a specific asset
    event VaultSet(address indexed asset, address indexed vault);

    /// @notice Event emitted when a deposit cap is set for a specific asset
    event DepositCapSet(address indexed asset, uint256 indexed cap);

    modifier onlyVaultFactory() {
        require(msg.sender == PRE_DEPOSIT_FACTORY, "!vaultFactory");
        _;
    }

    /// @notice Address of the WETH asset
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Address to hold the vault shares
    address public immutable SHARE_RECEIVER;

    /// @notice Address of the factory that deployed this contract
    address public immutable PRE_DEPOSIT_FACTORY;

    /// @notice Address of the Across bridge
    address public acrossBridge;

    /// @notice Address of the RelayLink bridge
    address public relayLinkBridge;

    /// @notice asset to stb depositor strategy for any deployed vaults
    mapping(address => address) public stbDepositor;

    /// @notice asset to vault mapping for any deployed vaults
    mapping(address => address) public preDepositVault;

    /// @notice Track deposit cap for each asset
    mapping(address => uint256) public depositCap;

    /// @notice Track total deposited amount for each asset
    /// Track asset instead of vault incase vault is updated
    mapping(address => uint256) public totalDeposited;

    /// @notice Track deposited amount for each asset and user
    /// @dev Use asset instead of vault incase vault is updated
    mapping(address => mapping(address => uint256)) public deposited;

    constructor(
        address _governance,
        address _acrossBridge,
        address _relayLinkBridge
    ) Governance2Step(_governance) {
        PRE_DEPOSIT_FACTORY = msg.sender;

        require(_acrossBridge != address(0), "ZERO_ADDRESS");
        acrossBridge = _acrossBridge;
        emit AcrossBridgeSet(_acrossBridge);

        require(_relayLinkBridge != address(0), "ZERO_ADDRESS");
        relayLinkBridge = _relayLinkBridge;
        emit RelayLinkBridgeSet(_relayLinkBridge);

        SHARE_RECEIVER = address(new ShareReceiver());
    }

    /// @notice function called by Across bridge when funds arrive
    function handleV3AcrossMessage(
        address _asset,
        uint256 _amount,
        address /* relayer */,
        bytes memory _message
    ) external {
        require(msg.sender == acrossBridge, "Invalid caller");
        (address _user, uint256 _originChainId, address _referral) = abi.decode(
            _message,
            (address, uint256, address)
        );

        _handleBridgeDeposit(_asset, _amount, _user, _originChainId, _referral);
    }

    /// @notice function called by RelayLink bridge when funds arrive
    function handleRelayLinkDeposit(
        address _asset,
        uint256 _amount,
        address _user,
        uint256 _originChainId,
        address _referral
    ) external {
        require(msg.sender == relayLinkBridge, "Invalid caller");
        _handleBridgeDeposit(_asset, _amount, _user, _originChainId, _referral);
    }

    function _handleBridgeDeposit(
        address _asset,
        uint256 _amount,
        address _user,
        uint256 _originChainId,
        address _referral
    ) internal {
        address _vault = preDepositVault[_asset];
        require(_vault != address(0), "Vault not set");
        // Funds should have been transferred to this contract before calling this function
        require(
            _amount > 0 && ERC20(_asset).balanceOf(address(this)) >= _amount,
            "Insufficient amount"
        );
        require(_user != address(0), "Invalid user");
        require(
            _originChainId != 0 && _originChainId != block.chainid,
            "Invalid chain id"
        );

        _deposit(_asset, _vault, _user, _amount, _originChainId, _referral);
    }

    function _deposit(
        address _asset,
        address _vault,
        address _user,
        uint256 _amount,
        uint256 _originChainId,
        address _referral
    ) internal {
        require(_amount <= maxDeposit(_asset), "Deposit cap exceeded");

        // Approve vault to spend assets
        ERC20(_asset).forceApprove(_vault, _amount);

        // Deposit into vault and send shares to recipient
        IVault(_vault).deposit(_amount, SHARE_RECEIVER);

        // Record deposit
        deposited[_asset][_user] += _amount;
        totalDeposited[_asset] += _amount;

        emit DepositProcessed(
            _asset,
            _user,
            _amount,
            _originChainId,
            _referral
        );
    }

    /// @notice Deposit assets into the vault
    /// @dev This is used by those on the same chain and default to no referral
    function deposit(address _asset, uint256 _amount) external {
        deposit(_asset, _amount, address(0));
    }

    /// @notice Deposit assets into the vault
    /// @dev This is used by those on the same chain.
    function deposit(
        address _asset,
        uint256 _amount,
        address _referral
    ) public {
        address vault = preDepositVault[_asset];
        require(vault != address(0), "Vault not set");
        require(_amount > 0, "Invalid amount");

        ERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        _deposit(_asset, vault, msg.sender, _amount, block.chainid, _referral);
    }

    /// @notice Deposit ETH into the vault
    /// @dev This is used by those on the same chain and default to no referral
    function depositEth() public payable {
        depositEth(address(0));
    }

    /// @notice Deposit ETH into the vault
    /// @dev This is used by those on the same chain.
    function depositEth(address _referral) public payable {
        address vault = preDepositVault[WETH];
        require(vault != address(0), "Vault not set");
        uint256 amount = msg.value;
        require(amount > 0, "Invalid amount");
        IWETH(WETH).deposit{value: amount}();

        _deposit(WETH, vault, msg.sender, amount, block.chainid, _referral);
    }

    /// @notice Get the max deposit amount for a specific asset
    /// @param _asset The asset address
    /// @return The max deposit amount
    function maxDeposit(address _asset) public view returns (uint256) {
        uint256 cap = depositCap[_asset];
        if (cap == type(uint256).max) {
            return cap;
        }

        uint256 totalDeposits = totalDeposited[_asset];
        if (totalDeposits >= cap) {
            return 0;
        }

        return cap - totalDeposits;
    }

    /// @notice Sets the deposit cap for a specific asset
    /// @dev Can only be called by the governance
    /// @param _asset The asset address
    /// @param _cap The new deposit cap
    function setDepositCap(
        address _asset,
        uint256 _cap
    ) external onlyGovernance {
        depositCap[_asset] = _cap;
        emit DepositCapSet(_asset, _cap);
    }

    /// @notice Sets the vault for a specific asset
    /// @dev Can only be called by the governance to override the vault
    /// @param _asset The asset address
    /// @param _vault The corresponding Pre-Deposit vault address
    function setVault(address _asset, address _vault) external onlyGovernance {
        require(_asset != address(0), "ZERO_ADDRESS");

        preDepositVault[_asset] = _vault;
        emit VaultSet(_asset, _vault);
    }

    /// @notice Sets the Across bridge
    /// @dev Set to address(0) to disable Across deposits
    /// @param _acrossBridge The new Across bridge address
    function setAcrossBridge(address _acrossBridge) external onlyGovernance {
        acrossBridge = _acrossBridge;

        emit AcrossBridgeSet(_acrossBridge);
    }

    /// @notice Sets the RelayLink bridge
    /// @dev Set to address(0) to disable RelayLink deposits
    /// @param _relayLinkBridge The new RelayLink bridge address
    function setRelayLinkBridge(
        address _relayLinkBridge
    ) external onlyGovernance {
        relayLinkBridge = _relayLinkBridge;

        emit RelayLinkBridgeSet(_relayLinkBridge);
    }

    /// @notice Notify relayer of new vault
    /// @dev Can only be called by the vault factory
    /// @param _asset The asset address
    /// @param _vault The corresponding Pre-Deposit vault address
    /// @param _stbStrategy The corresponding STB depositor strategy address
    function newVault(
        address _asset,
        address _vault,
        address _stbStrategy
    ) external onlyVaultFactory {
        require(_asset != address(0), "ZERO_ADDRESS");

        preDepositVault[_asset] = _vault;
        stbDepositor[_asset] = _stbStrategy;
        depositCap[_asset] = type(uint256).max;
    }

    function rescue(address _token) external onlyGovernance {
        ERC20(_token).safeTransfer(
            msg.sender,
            ERC20(_token).balanceOf(address(this))
        );
    }
}
