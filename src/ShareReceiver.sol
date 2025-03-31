// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

contract ShareReceiver is Governance2Step {
    using SafeERC20 for ERC20;

    constructor(address _governance) Governance2Step(_governance) {}

    function pullShares(address token, uint256 amount) external onlyGovernance {
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice This is called by the vault during maxDeposit checks. It will
    ///  only allow deposits into the vault if the receiver is this address.
    function available_deposit_limit(
        address _receiver
    ) external view returns (uint256) {
        if (_receiver == address(this)) {
            return type(uint256).max;
        }
        return 0;
    }

    /// @notice This is called by the vault during maxWithdraw checks. It will prevent any withdrawals
    function available_withdraw_limit(
        address,
        uint256,
        address[] memory
    ) external view returns (uint256) {
        return 0;
    }
}
