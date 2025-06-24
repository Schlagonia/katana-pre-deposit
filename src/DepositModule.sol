// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Governance} from "@periphery/utils/Governance.sol";

contract DepositModule is Governance {
    address public immutable SHARE_RECEIVER;

    mapping(address => uint256) public depositCap;

    constructor(
        address _governance,
        address _shareReceiver
    ) Governance(_governance) {
        SHARE_RECEIVER = _shareReceiver;
    }

    function setDepositCap(
        address _vault,
        uint256 _cap
    ) external onlyGovernance {
        depositCap[_vault] = _cap;
    }

    function available_deposit_limit(
        address _receiver
    ) external view returns (uint256) {
        if (_receiver == SHARE_RECEIVER) {
            return 0;
        }
        return depositCap[msg.sender];
    }
}
