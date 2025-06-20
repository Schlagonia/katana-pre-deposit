// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {DepositRelayer} from "./DepositRelayer.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Accountant {
    using SafeERC20 for ERC20;

    modifier onlyGovernance() {
        require(msg.sender == DEPOSIT_RELAYER.governance(), "!governance");
        _;
    }

    DepositRelayer public immutable DEPOSIT_RELAYER;

    constructor(address _depositRelayer) {
        DEPOSIT_RELAYER = DepositRelayer(_depositRelayer);
    }

    function report(
        address,
        uint256 _gain,
        uint256 _loss
    ) public virtual returns (uint256 totalFees, uint256) {
        // Should not take on losses
        require(_loss == 0, "loss too high");

        // We take a 100% fee on the gain
        totalFees = _gain;
    }

    function sweep(address _token) external onlyGovernance {
        ERC20(_token).safeTransfer(
            msg.sender,
            ERC20(_token).balanceOf(address(this))
        );
    }
}
