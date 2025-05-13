// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PreDepositFactory} from "../src/PreDepositFactory.sol";
import {DepositRelayer} from "../src/DepositRelayer.sol";
contract Deploy is Script {

    address public governance = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public acrossBridge = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address public relayLinkBridge = 0xeeeeee9eC4769A09a76A83C7bC42b185872860eE;
    address public roleManager = 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41;
    address public deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public asset;
    address public yearnVault;
    address public stbVault;

    function run() public {
        vm.startBroadcast();

        PreDepositFactory preDepositFactory = new PreDepositFactory(deployer, acrossBridge, relayLinkBridge, roleManager);

        console.log("PreDepositFactory deployed to:", address(preDepositFactory));
        console.log("DepositRelayer deployed to:", address(preDepositFactory.DEPOSIT_RELAYER()));
        console.log("Accountant deployed to:", address(preDepositFactory.ACCOUNTANT()));
        console.log("ShareReceiver deployed to:", address(preDepositFactory.DEPOSIT_RELAYER().SHARE_RECEIVER()));

        // USDC
        asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        yearnVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        stbVault = 0x694E47AFD14A64661a04eee674FB331bCDEF3737;

        address usdcVault = preDepositFactory.deployPreDeposit(asset, yearnVault, stbVault);
        console.log("USDC PreDeposit deployed to:", usdcVault);

        // USDT
        asset = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        yearnVault = 0x310B7Ea7475A0B449Cfd73bE81522F1B88eFAFaa;
        stbVault = 0x6D2981FF9b8d7edbb7604de7A65BAC8694ac849F;

        address usdtVault = preDepositFactory.deployPreDeposit(asset, yearnVault, stbVault);
        console.log("USDT PreDeposit deployed to:", usdtVault);

        // WBTC
        asset = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        yearnVault = 0x751F0cC6115410A3eE9eC92d08f46Ff6Da98b708;
        stbVault = 0xF18245B7B7bA6c9c3Bf29B070ebea893d8FC549d;

        address wbtcVault = preDepositFactory.deployPreDeposit(asset, yearnVault, stbVault);
        console.log("WBTC PreDeposit deployed to:", wbtcVault);

        // weth
        asset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        yearnVault = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
        stbVault = 0xeEB6Be70fF212238419cD638FAB17910CF61CBE7;

        address wethVault = preDepositFactory.deployPreDeposit(asset, yearnVault, stbVault);
        console.log("WETH PreDeposit deployed to:", wethVault);

        DepositRelayer depositRelayer = DepositRelayer(preDepositFactory.DEPOSIT_RELAYER());
        depositRelayer.transferGovernance(governance);

        vm.stopBroadcast();
    }
}
