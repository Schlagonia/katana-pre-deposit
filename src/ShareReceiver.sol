// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

contract ShareReceiver {
    address public immutable DEPOSIT_RELAYER;

    constructor() {
        DEPOSIT_RELAYER = msg.sender;
    }
}
