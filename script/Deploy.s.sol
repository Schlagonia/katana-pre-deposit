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

    address public preDepositFactory = 0x9d770717d63e32089B2E11E4Ce927C1dCe8A023d;

    function run() public {
        vm.startBroadcast();

        // USDC
        asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        vbVault = 0x53E82ABbb12638F09d9e624578ccB666217a765e;
        preDepositVault = 0x7B5A0182E400b241b317e781a4e9dEdFc1429822;

        STBDepositor usdcSTBDepositor = new STBDepositor(asset, name(asset), vbVault, preDepositVault, preDepositFactory);
        console.log(IStrategyInterface(address(usdcSTBDepositor)).name(), " deployed to:", address(usdcSTBDepositor));
        setAddresses(address(usdcSTBDepositor));

        // USDT
        asset = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        vbVault = 0x6d4f9f9f8f0155509ecd6Ac6c544fF27999845CC;
        preDepositVault = 0x48c03B6FfD0008460F8657Db1037C7e09dEedfcb;

        STBDepositor usdtSTBDepositor = new STBDepositor(asset, name(asset), vbVault, preDepositVault, preDepositFactory);
        console.log(IStrategyInterface(address(usdtSTBDepositor)).name(), " deployed to:", address(usdtSTBDepositor));
        setAddresses(address(usdtSTBDepositor));

        // WBTC
        asset = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        vbVault = 0x2C24B57e2CCd1f273045Af6A5f632504C432374F;
        preDepositVault = 0x92C82f5F771F6A44CfA09357DD0575B81BF5F728;

        STBDepositor wbtcSTBDepositor = new STBDepositor(asset, name(asset), vbVault, preDepositVault, preDepositFactory);
        console.log(IStrategyInterface(address(wbtcSTBDepositor)).name(), " deployed to:", address(wbtcSTBDepositor));
        setAddresses(address(wbtcSTBDepositor));

        // weth
        asset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        vbVault = 0x2DC70fb75b88d2eB4715bc06E1595E6D97c34DFF;
        preDepositVault = 0xcc6a16Be713f6a714f68b0E1f4914fD3db15fBeF;

        STBDepositor wethSTBDepositor = new STBDepositor(asset, name(asset), vbVault, preDepositVault, preDepositFactory);
        console.log(IStrategyInterface(address(wethSTBDepositor)).name(), " deployed to:", address(wethSTBDepositor));
        setAddresses(address(wethSTBDepositor));

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

    function setAddresses(address stbDepositor) public {
        IStrategyInterface _stbDepositor = IStrategyInterface(stbDepositor);
        _stbDepositor.setPendingManagement(governance);
        _stbDepositor.setPerformanceFeeRecipient(governance);
        _stbDepositor.setKeeper(governance);
        _stbDepositor.setEmergencyAdmin(sms);
    }
}
