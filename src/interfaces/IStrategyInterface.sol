// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function bridgeFunds() external;

    function setKatanaReceiver(address _katanaReceiver) external;

    function katanaReceiver() external view returns (address);

    function LXLY_BRIDGE() external view returns (address);
}
