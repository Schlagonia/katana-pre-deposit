// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

interface IAccountant {
    function setCustomConfig(
        address vault,
        uint16 customManagement,
        uint16 customPerformance,
        uint16 customRefund,
        uint16 customMaxFee,
        uint16 customMaxGain,
        uint16 customMaxLoss
    ) external;
    function removeCustomConfig(address vault) external;
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
        require(
            canReport[msg.sender] || msg.sender == governance,
            "!authorized"
        );
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
        IAccountant(ACCOUNTANT).setCustomConfig(vault, 0, 0, 0, 0, 0, 0);

        // Trigger the vault to report on itself
        (gain, loss) = IVault(vault).process_report(vault);

        IAccountant(ACCOUNTANT).removeCustomConfig(vault);

        // Post-report sanity checks
        require(gain == expectedGain, "gain mismatch");
        // Verify PPS hasn't increased
        require(IVault(vault).pricePerShare() == prePPS, "PPS changed");
        // Total idle should have increased by the expected gain
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
    fallback() external {
        _checkGovernance();

        (bool success, bytes memory result) = ACCOUNTANT.call(msg.data);

        if (success) {
            assembly {
                return(add(result, 0x20), mload(result))
            }
        } else {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }
}
