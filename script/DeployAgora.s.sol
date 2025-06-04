// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AgoraStrategy} from "../src/AgoraStrategy.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

// Dry run:
// forge script script/DeployAgora.s.sol --rpc-url $ETH_RPC_URL --account DEPLOYER_ACCOUNT

// Live run:
// forge script script/DeployAgora.s.sol --rpc-url $ETH_RPC_URL --account DEPLOYER_ACCOUNT --broadcast --verify

contract DeployAgora is Script {

    /// @notice Global v3.0.4 vault factory
    IVaultFactory public constant VAULT_FACTORY =
        IVaultFactory(0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F);

    // AUSD
    address public asset = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;

    ////////// FILL IN THESE VALUES //////////

    // Address to be able to withdraw funds from the strategy.
    address public fundManager;

    // Trusted address to own and manage the Vault and strategy.
    address public roleManager;

    // Address that will be running the deployment script. Can be the same as the roleManager.
    address public deployer;

    uint256 public depositLimit;

    function run() public {
        vm.startBroadcast();

        // Deploy new multi strategy vault.
        address _vault = VAULT_FACTORY.deploy_new_vault(asset, "Katana Pre-Deposit AUSD ", "kpdAUSD", deployer, 60*60*24*7);
        console.log("Vault deployed to:", _vault);

        IVault vault = IVault(_vault);

        AgoraStrategy agoraStrategy = new AgoraStrategy(asset, fundManager, _vault);
        console.log("Agora Strategy deployed to:", address(agoraStrategy));

        IStrategyInterface strategy = IStrategyInterface(address(agoraStrategy));

        // NOTE: The `roleManager` will need to accept these with `.acceptManagement()`
        strategy.setPendingManagement(roleManager);
        strategy.setKeeper(roleManager);
        strategy.setEmergencyAdmin(roleManager);
        strategy.setPerformanceFeeRecipient(roleManager);

        // Setup Vault

        // Temporary give deployer all roles
        vault.set_role(deployer, Roles.ALL);

        // Set deposit limit
        vault.set_deposit_limit(depositLimit);

        // Add Agora Strategy
        vault.add_strategy(address(strategy));
        vault.update_max_debt_for_strategy(address(strategy), depositLimit);

        // Take away all the roles.
        vault.set_role(deployer, 0);

        // Transfer to final Role Manager
        // NOTE: The `roleManager` will need to accept this with `.accept_role_manager()`
        vault.transfer_role_manager(roleManager);

        vm.stopBroadcast();
    }   
}