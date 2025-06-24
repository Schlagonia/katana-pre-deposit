// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;


contract DepositModule {
    address public immutable SHARE_RECEIVER;

    constructor(address _shareReceiver){
        SHARE_RECEIVER = _shareReceiver;
    }

    function available_deposit_limit(address _receiver) external view returns (uint256) {
        if(_receiver == SHARE_RECEIVER){
            return 0;
        }
        return type(uint256).max;
    }
}