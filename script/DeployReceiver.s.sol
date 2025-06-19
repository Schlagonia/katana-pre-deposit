// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KatanaReceiver} from "../src/KatanaReceiver.sol";

contract DeployReceiver is Script {
    address public governance = 0xe6ad5A88f5da0F276C903d9Ac2647A937c917162;

    function run() public {
        vm.startBroadcast();

        KatanaReceiver katanaReceiver = new KatanaReceiver(governance);
        console.log("KatanaReceiver deployed to:", address(katanaReceiver));

        vm.stopBroadcast();
    }
}