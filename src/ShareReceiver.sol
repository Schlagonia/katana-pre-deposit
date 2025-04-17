// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DepositRelayer} from "./DepositRelayer.sol";

contract ShareReceiver {
    using SafeERC20 for ERC20;

    modifier onlyGovernance() {
        require(
            msg.sender == DepositRelayer(DEPOSIT_RELAYER).governance(),
            "!governance"
        );
        _;
    }

    address public immutable DEPOSIT_RELAYER;

    constructor() {
        DEPOSIT_RELAYER = msg.sender;
    }

    function pullShares(address token, uint256 amount) external onlyGovernance {
        ERC20(token).safeTransfer(msg.sender, amount);
    }
}
