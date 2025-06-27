// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {IPolygonZkEVMBridge} from "./interfaces/IPolygonZkEVMBridge.sol";

contract L1Claimer is Governance {
    IPolygonZkEVMBridge public constant ZKEVM_BRIDGE =
        IPolygonZkEVMBridge(0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe);

    uint32 public constant ROLLUP_ID = 20;

    /// @notice Mapping of L1 Pre-Deposit vault to Katana Merkle Distributor address.
    mapping(address => address) public claimContracts;

    constructor(address _governance) Governance(_governance) {}

    function setClaimContract(
        address _vault,
        address _claimContract
    ) external onlyGovernance {
        claimContracts[_vault] = _claimContract;
    }

    function claim(
        address _vault,
        uint256 _amount,
        address _recipient,
        bytes32[] memory _proof
    ) external {
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
}
