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
}
