// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PreDepositFactory} from "../src/PreDepositFactory.sol";
import {DepositRelayer} from "../src/DepositRelayer.sol";
import {STBDepositor} from "../src/STBDepositor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

contract Deploy is Script {

    address public governance = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public sms = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address public acrossBridge = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address public relayLinkBridge = 0xeeeeee9eC4769A09a76A83C7bC42b185872860eE;
    address public roleManager = 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41;
    address public deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public asset;
    address public vbVault;
    address public preDepositVault;
    address public yearnVault;

    function run() public {
        vm.startBroadcast();

        PreDepositFactory preDepositFactory = new PreDepositFactory(deployer, acrossBridge, relayLinkBridge, roleManager);
        DepositRelayer depositRelayer = preDepositFactory.DEPOSIT_RELAYER();
        console.log("preDepositFactory deployed to:", address(preDepositFactory));

        // USDC
        asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        vbVault = 0x53E82ABbb12638F09d9e624578ccB666217a765e;
        yearnVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;

        address usdcPreDepositVault = preDepositFactory.deployPreDeposit(asset, yearnVault, vbVault);   
        depositRelayer.setDepositCap(asset, 0);
        console.log("usdcPreDepositVault deployed to:", usdcPreDepositVault);

        // USDT
        asset = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        vbVault = 0x6d4f9f9f8f0155509ecd6Ac6c544fF27999845CC;
        yearnVault = 0x310B7Ea7475A0B449Cfd73bE81522F1B88eFAFaa;

        address usdtPreDepositVault = preDepositFactory.deployPreDeposit(asset, yearnVault, vbVault);
        depositRelayer.setDepositCap(asset, 0);
        console.log("usdtPreDepositVault deployed to:", usdtPreDepositVault);

        // WBTC
        asset = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        vbVault = 0x2C24B57e2CCd1f273045Af6A5f632504C432374F;
        yearnVault = 0x751F0cC6115410A3eE9eC92d08f46Ff6Da98b708;

        address wbtcPreDepositVault = preDepositFactory.deployPreDeposit(asset, yearnVault, vbVault);
        depositRelayer.setDepositCap(asset, 0);
        console.log("wbtcPreDepositVault deployed to:", wbtcPreDepositVault);

        // weth
        asset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        vbVault = 0x2DC70fb75b88d2eB4715bc06E1595E6D97c34DFF;
        yearnVault = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
        address wethPreDepositVault = preDepositFactory.deployPreDeposit(asset, yearnVault, vbVault);
        depositRelayer.setDepositCap(asset, 0);
        console.log("wethPreDepositVault deployed to:", wethPreDepositVault);

        depositRelayer.transferGovernance(governance);

        vm.stopBroadcast();
    }

    function name(address _asset) public view returns (string memory) {
        return string(
            abi.encodePacked(
                "Katana ",
                ERC20(_asset).symbol(),
                " STB Depositor"
            )
        );
    }

}
