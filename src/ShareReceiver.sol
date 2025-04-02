// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DepositRelayer} from "./DepositRelayer.sol";

// TODO:
//  Allow certain addresses to withdraw?
contract ShareReceiver {
    using SafeERC20 for ERC20;

    modifier onlyGovernance() {
        require(
            msg.sender == DepositRelayer(DEPOSIT_RELAYER).governance(),
            "Invalid caller"
        );
        _;
    }

    modifier onlyDepositRelayer() {
        require(msg.sender == DEPOSIT_RELAYER, "Invalid caller");
        _;
    }

    address public immutable DEPOSIT_RELAYER;

    /// @notice Track deposited amount for each token and user
    /// @dev Use token instead of vault incase vault is updated
    mapping(address => mapping(address => uint256)) public deposited;

    constructor() {
        DEPOSIT_RELAYER = msg.sender;
    }

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
    /// TODO: Call through this contract? OR just tansfer shares if TT and no limit module
    function available_withdraw_limit(
        address,
        uint256,
        address[] memory
    ) external view returns (uint256) {
        return 0;
    }

    function depositProcessed(
        address token,
        address user,
        uint256 amount
    ) external onlyDepositRelayer {
        deposited[token][user] += amount;
    }
}
