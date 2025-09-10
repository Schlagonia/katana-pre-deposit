// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AccountantProxy} from "../src/AccountantProxy.sol";

contract DeployAccountantProxy is Script {
    address public governance = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address public accountant = 0x1f399808fE52d0E960CAB84b6b54d5707ab27c8a; 

    function run() public {
        vm.startBroadcast();

        AccountantProxy accountantProxy = new AccountantProxy(accountant, governance);
        console.log("AccountantProxy deployed to:", address(accountantProxy));

        vm.stopBroadcast();
    }
}