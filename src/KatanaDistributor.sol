// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Governance} from "@periphery/utils/Governance.sol";

/// @title KatanaDistributor
/// @notice Claim from merkle tree either directly on L2 or through L1 claimer.
contract KatanaDistributor is Governance {
    using SafeERC20 for ERC20;

    /// @notice The address of the ZKEVM bridge.
    address public constant ZKEVM_BRIDGE =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    /// @notice The address of the vault this claimer distributes.
    address public immutable VAULT;

    /// @notice The address of the L1 claimer.
    address public immutable L1_CLAIMER;

    /// @notice The merkle tree's root of the current rewards distribution.
    bytes32 public currentRoot;

    /// @notice If rewards have already been claimed.
    mapping(address => bool) public claimed;

    /// EVENTS ///

    /// @notice Emitted when the root is updated.
    /// @param newRoot The new merkle's tree root.
    event RootUpdated(bytes32 indexed newRoot);

    /// @notice Emitted when tokens are withdrawn.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawn(
        address indexed token,
        address indexed to,
        uint256 indexed amount
    );

    /// @notice Emitted when an account claims rewards.
    /// @param account The address of the claimer.
    /// @param amount The amount of rewards claimed.
    event RewardsClaimed(
        address indexed token,
        address indexed account,
        address indexed recipient,
        uint256 amount
    );

    /// CONSTRUCTOR ///

    constructor(
        address _governance,
        address _vault,
        address _l1Claimer
    ) Governance(_governance) {
        VAULT = _vault;
        L1_CLAIMER = _l1Claimer;
    }

    /// EXTERNAL ///

    /// @notice Updates the current merkle tree's root.
    /// @param _newRoot The new merkle tree's root.
    function updateRoot(bytes32 _newRoot) external onlyGovernance {
        currentRoot = _newRoot;
        emit RootUpdated(_newRoot);
    }

    /// @notice Withdraws tokens to a recipient.
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens to transfer.
    function withdrawTokens(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyGovernance {
        uint256 balance = ERC20(_token).balanceOf(address(this));
        uint256 toWithdraw = balance < _amount ? balance : _amount;
        ERC20(_token).safeTransfer(_to, toWithdraw);
        emit Withdrawn(_token, _to, toWithdraw);
    }

    /// @notice Handles the message received from the ZKEVM bridge.
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable {
        // Can only be called by the bridge
        require(ZKEVM_BRIDGE == msg.sender, "!bridge");
        require(L1_CLAIMER == originAddress, "!l1Claimer");
        require(0 == originNetwork, "!mainnet");

        (
            address _account,
            uint256 _amount,
            address _recipient,
            bytes32[] memory _proof
        ) = abi.decode(data, (address, uint256, address, bytes32[]));

        _claim(_account, _amount, _recipient, _proof);
    }

    /// @notice Claims rewards to self.
    /// @param _amount The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function claim(uint256 _amount, bytes32[] memory _proof) external {
        _claim(msg.sender, _amount, msg.sender, _proof);
    }

    /// @notice Claims rewards to a recipient.
    /// @param _amount The overall claimable amount of token rewards.
    /// @param _recipient The address of the recipient.
    /// @param _proof The merkle proof that validates this claim.
    function claim(
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) external {
        _claim(msg.sender, _amount, _recipient, _proof);
    }

    /// @notice Internal function to claim rewards.
    function _claim(
        address _account,
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) internal {
        require(!claimed[_account], "Already claimed");

        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(_account, _amount)))
        );

        require(MerkleProof.verify(_proof, currentRoot, leaf), "Invalid proof");

        claimed[_account] = true;

        ERC20(VAULT).safeTransfer(_recipient, _amount);
        emit RewardsClaimed(VAULT, _account, _recipient, _amount);
    }
}
