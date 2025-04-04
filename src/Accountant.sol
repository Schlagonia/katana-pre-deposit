// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {PreDepositFactory} from "./PreDepositFactory.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Accountant {
    using SafeERC20 for ERC20;

    modifier onlyGovernance() {
        require(
            msg.sender == PreDepositFactory(PRE_DEPOSIT_FACTORY).governance(),
            "!governance"
        );
        _;
    }

    PreDepositFactory public immutable PRE_DEPOSIT_FACTORY;

    constructor() {
        PRE_DEPOSIT_FACTORY = PreDepositFactory(msg.sender);
    }

    function report(
        address,
        uint256 gain,
        uint256 loss
    ) public virtual returns (uint256 totalFees, uint256) {
        require(
            PRE_DEPOSIT_FACTORY.preDepositVault(IVault(msg.sender).asset()) ==
                msg.sender,
            "Invalid vault"
        );
        // Should not take on losses
        require(loss == 0, "loss too high");

        // We take a 100% fee on the gain
        totalFees = gain;
    }

    function sweep(address token) external onlyGovernance {
        ERC20(token).safeTransfer(
            msg.sender,
            ERC20(token).balanceOf(address(this))
        );
    }
}
