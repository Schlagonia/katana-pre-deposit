// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {DepositRelayer} from "./DepositRelayer.sol";

contract ShareReceiver {
    using SafeERC20 for ERC20;

    modifier onlyGovernance() {
        require(
            msg.sender == Governance2Step(PRE_DEPOSIT_FACTORY).governance(),
            "!governance"
        );
        _;
    }

    modifier onlyDepositRelayer() {
        require(msg.sender == DEPOSIT_RELAYER, "!depositRelayer");
        _;
    }

    address public immutable DEPOSIT_RELAYER;

    address public immutable PRE_DEPOSIT_FACTORY;

    /// @notice Track deposited amount for each token and user
    /// @dev Use token instead of vault incase vault is updated
    mapping(address => mapping(address => uint256)) public deposited;

    constructor(address _preDepositFactory) {
        DEPOSIT_RELAYER = msg.sender;
        PRE_DEPOSIT_FACTORY = _preDepositFactory;
    }

    function pullShares(address token, uint256 amount) external onlyGovernance {
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    function depositProcessed(
        address token,
        address user,
        uint256 amount
    ) external onlyDepositRelayer {
        deposited[token][user] += amount;
    }
}
