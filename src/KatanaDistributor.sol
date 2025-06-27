// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Governance} from "@periphery/utils/Governance.sol";

contract RewardsDistributor is Governance {
    using SafeERC20 for ERC20;

    /// STORAGE ///
    address public constant ZKEVM_BRIDGE =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    address public immutable VAULT;

    address public immutable L1_CLAIMER;

    bytes32 public currentRoot; // The merkle tree's root of the current rewards distribution.

    mapping(address => bool) public claimed; // The rewards already claimed. account -> amount.

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

    /// ERRORS ///

    /// @notice Thrown when the proof is invalid or expired.
    error ProofInvalidOrExpired();

    /// @notice Thrown when the claimer has already claimed the rewards.
    error AlreadyClaimed();

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

    function claim(uint256 _amount, bytes32[] memory _proof) external {
        _claim(msg.sender, _amount, msg.sender, _proof);
    }

    function claim(
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) external {
        _claim(msg.sender, _amount, _recipient, _proof);
    }

    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _amount The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function _claim(
        address _account,
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) internal {
        if (claimed[_account]) revert AlreadyClaimed();

        if (
            !MerkleProof.verify(
                _proof,
                currentRoot,
                keccak256(abi.encodePacked(_account, _amount))
            )
        ) revert ProofInvalidOrExpired();

        claimed[_account] = true;

        ERC20(VAULT).safeTransfer(_recipient, _amount);
        emit RewardsClaimed(VAULT, _account, _recipient, _amount);
    }
}
