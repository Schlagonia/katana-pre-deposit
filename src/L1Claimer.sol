// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {IPolygonZkEVMBridge} from "./interfaces/IPolygonZkEVMBridge.sol";

/// @title L1Claimer
/// @notice A contract that allows L1 to claim rewards on L2 to a different address.
contract L1Claimer is Governance {
    /// EVENTS ///

    /// @notice Emitted when the claim contract is set.
    /// @param vault The vault to set the claim contract for.
    /// @param claimContract The address of the Katana Merkle Distributor.
    event ClaimContractSet(
        address indexed vault,
        address indexed claimContract
    );

    IPolygonZkEVMBridge public constant ZKEVM_BRIDGE =
        IPolygonZkEVMBridge(0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe);

    /// @notice Katana rollup ID.
    uint32 public constant ROLLUP_ID = 20;

    /// @notice Mapping of L1 Pre-Deposit vault to Katana Merkle Distributor address.
    mapping(address => address) public claimContracts;

    constructor(address _governance) Governance(_governance) {}

    /// @notice Set the Katana Merkle Distributor address for a given vault.
    /// @param _vault The vault to set the claim contract for.
    /// @param _claimContract The address of the Katana Merkle Distributor.
    function setClaimContract(
        address _vault,
        address _claimContract
    ) external onlyGovernance {
        claimContracts[_vault] = _claimContract;
        emit ClaimContractSet(_vault, _claimContract);
    }

    /// @notice Claim the vault shares through an L1 txn and specify the recipient.
    /// @param _vault The vault to claim shares from.
    /// @param _amount The amount of shares to claim.
    /// @param _recipient The recipient of the shares on L2.
    /// @param _proof The proof of the claim.
    function claim(
        address _vault,
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) public {
        address claimContract = claimContracts[_vault];
        require(claimContract != address(0), "!claimContract");

        // Send Message to Bridge for Katana claimer
        ZKEVM_BRIDGE.bridgeMessage(
            ROLLUP_ID,
            claimContract,
            true,
            abi.encode(msg.sender, _amount, _recipient, _proof)
        );
    }

    /// @notice Claim the vault shares through an L1 txn and specify the recipient.
    /// @param _vaults The vaults to claim shares from.
    /// @param _amounts The amounts of shares to claim.
    /// @param _recipients The recipients of the shares on L2.
    /// @param _proofs The proofs of the claims.
    function multiClaim(
        address[] memory _vaults,
        uint256[] memory _amounts,
        address[] memory _recipients,
        bytes32[][] memory _proofs
    ) external {
        require(_vaults.length == _amounts.length, "!length");
        require(_vaults.length == _recipients.length, "!length");
        require(_vaults.length == _proofs.length, "!length");

        for (uint256 i = 0; i < _vaults.length; i++) {
            claim(_vaults[i], _amounts[i], _recipients[i], _proofs[i]);
        }
    }
}
