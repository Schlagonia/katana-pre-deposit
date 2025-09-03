// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

interface IAccountant {
    function turnOffHealthCheck(address vault, address strategy) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title AccountantProxy
 * @notice Proxy contract that wraps an Accountant to allow authorized addresses to trigger self-reporting
 * @dev Acts as a pass-through for all other accountant functions while adding self-reporting capability
 */
contract AccountantProxy is Governance {
    // Events
    event ReporterSet(address indexed reporter, bool authorized);

    // State variables
    address public immutable ACCOUNTANT;

    mapping(address => bool) public canReport;

    modifier onlyReporter() {
        require(canReport[msg.sender], "!authorized");
        _;
    }

    /**
     * @notice Constructor to set the accountant address and governance
     * @param _accountant Address of the underlying accountant contract
     * @param _governance Address of the governance
     */
    constructor(
        address _accountant,
        address _governance
    ) Governance(_governance) {
        require(_accountant != address(0), "zero address");
        ACCOUNTANT = _accountant;
    }

    /**
     * @notice Allows authorized addresses to trigger self-reporting for a vault
     * @param vault Address of the vault to report on itself
     * @return gain Amount of gain reported
     * @return loss Amount of loss reported
     */
    function reportOnSelf(
        address vault
    ) external onlyReporter returns (uint256 gain, uint256 loss) {
        // Store pre-report state
        uint256 preTotalAssets = IVault(vault).totalAssets();
        uint256 preTotalIdle = IVault(vault).totalIdle();
        uint256 prePPS = IVault(vault).pricePerShare();

        // Get the actual asset balance to determine expected gain
        address asset = IVault(vault).asset();
        uint256 vaultAssetBalance = IERC20(asset).balanceOf(vault);
        uint256 expectedGain = vaultAssetBalance - preTotalIdle;

        require(expectedGain > 0, "no gain");

        // Turn off health check for self-reporting
        IAccountant(ACCOUNTANT).turnOffHealthCheck(vault, vault);

        // Trigger the vault to report on itself
        (gain, loss) = IVault(vault).process_report(vault);

        // Post-report sanity checks
        require(gain == expectedGain, "gain mismatch");
        // Verify PPS hasn't increased (allowing for rounding)
        require(IVault(vault).pricePerShare() == prePPS, "PPS changed");
        // Account for fees reducing the idle increase
        require(
            IVault(vault).totalIdle() == preTotalIdle + expectedGain,
            "Idle update incorrect"
        );

        // Verify total assets changed as expected
        require(
            IVault(vault).totalAssets() == preTotalAssets + expectedGain,
            "Total assets mismatch"
        );
        require(loss == 0, "loss is not 0");

        return (gain, loss);
    }

    /**
     * @notice Set or remove reporter authorization for an address
     * @param reporter Address to set authorization for
     * @param authorized Whether the address should be authorized
     */
    function setReporter(
        address reporter,
        bool authorized
    ) external onlyGovernance {
        require(reporter != address(0), "zero address");
        require(canReport[reporter] != authorized, "already set");

        canReport[reporter] = authorized;

        emit ReporterSet(reporter, authorized);
    }

    /**
     * @notice Fallback function to forward all other calls to the accountant
     * @dev Validates permissions based on function selector before forwarding
     */
    fallback() external payable {
        _checkGovernance();

        address _accountant = ACCOUNTANT;

        assembly {
            // Copy calldata to memory
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())

            // Forward call to accountant
            let result := call(
                gas(),
                _accountant,
                callvalue(),
                ptr,
                calldatasize(),
                0,
                0
            )

            // Copy return data
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            // Return or revert based on result
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    /**
     * @notice Receive function to handle plain ETH transfers
     * @dev Reverts as this contract should not hold ETH
     */
    receive() external payable {
        revert("No ETH accepted");
    }
}
