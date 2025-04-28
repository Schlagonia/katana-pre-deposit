// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PreDepositFactory} from "../src/PreDepositFactory.sol";

contract Deploy is Script {

    address public governance;
    address public acrossBridge = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address public relayLinkBridge = 0xeeeeee9eC4769A09a76A83C7bC42b185872860eE;
    uint32 public targetNetworkId = 1;
    address public roleManager;

    address public asset;
    address public yearnVault;
    address public stbVault;

    function run() public {
        vm.startBroadcast();

        PreDepositFactory preDepositFactory = new PreDepositFactory(governance, acrossBridge, relayLinkBridge, targetNetworkId, roleManager);

        console.log("PreDepositFactory deployed to:", address(preDepositFactory));
        console.log("DepositRelayer deployed to:", address(preDepositFactory.DEPOSIT_RELAYER()));
        console.log("Accountant deployed to:", address(preDepositFactory.ACCOUNTANT()));
        console.log("ShareReceiver deployed to:", address(preDepositFactory.DEPOSIT_RELAYER().SHARE_RECEIVER()));

        vm.stopBroadcast();
    }
}
