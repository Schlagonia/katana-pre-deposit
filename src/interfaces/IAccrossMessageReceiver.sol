// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface IAccrossMessageReceiver {
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address relayer,
        bytes memory message
    ) external;
}
