// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PreDepositFactory} from "../src/PreDepositFactory.sol";

contract Deploy is Script {

    address public governance = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address public acrossBridge = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address public relayLinkBridge = 0xeeeeee9eC4769A09a76A83C7bC42b185872860eE;
    uint32 public targetNetworkId = 1;
    address public roleManager = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public yearnVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
    address public stbVault = 0xAe7d8Db82480E6d8e3873ecbF22cf17b3D8A7308;

    function run() public {
        vm.startBroadcast();

        PreDepositFactory preDepositFactory = new PreDepositFactory(governance, acrossBridge, relayLinkBridge, targetNetworkId, roleManager);

        console.log("PreDepositFactory deployed to:", address(preDepositFactory));

        address preDepositVault = preDepositFactory.deployPreDeposit(address(asset), address(yearnVault), address(stbVault));

        console.log("PreDepositVault deployed to:", address(preDepositVault));

        console.log("DepositRelayer deployed to:", address(preDepositFactory.DEPOSIT_RELAYER()));
        console.log("Accountant deployed to:", address(preDepositFactory.ACCOUNTANT()));
        console.log("ShareReceiver deployed to:", address(preDepositFactory.DEPOSIT_RELAYER().SHARE_RECEIVER()));
        console.log("STBDepositor deployed to:", address(preDepositFactory.DEPOSIT_RELAYER().stbDepositor(address(asset))));

        vm.stopBroadcast();
    }
}
