// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {KatanaReceiver} from "../KatanaReceiver.sol";

contract TestReceiver is Setup {
    KatanaReceiver public receiver;

    event VaultSet(address indexed asset, address indexed vault);

    function setUp() public override {
        super.setUp();
        receiver = new KatanaReceiver(management);
    }

    function test_setVault() public {
        vm.startPrank(management);

        vm.expectEmit(true, true, false, false);
        emit VaultSet(address(asset), address(preDepositVault));

        receiver.setVault(address(asset), address(preDepositVault));
        assertEq(receiver.vaults(address(asset)), address(preDepositVault));

        vm.stopPrank();
    }

    function test_RevertWhen_NonGovernanceSetsVault() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        receiver.setVault(address(asset), address(preDepositVault));
    }

    function test_deposit() public {
        // Set vault first
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        // Airdrop tokens to receiver
        uint256 amount = 1000 * 10 ** decimals;
        airdrop(asset, address(receiver), amount);

        // Deposit tokens
        receiver.deposit(address(asset));

        // Check balances
        assertEq(asset.balanceOf(address(receiver)), 0, "!receiver balance");
        assertEq(
            preDepositVault.balanceOf(address(receiver)),
            amount,
            "!vault balance"
        );
    }

    function test_RevertWhen_DepositingWithoutVault() public {
        uint256 amount = 1000 * 10 ** decimals;
        airdrop(asset, address(receiver), amount);

        vm.expectRevert("Vault not found");
        receiver.deposit(address(asset));
    }

    function test_RevertWhen_DepositingZeroBalance() public {
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        vm.expectRevert("No balance");
        receiver.deposit(address(asset));
    }

    function test_disperse() public {
        // Set vault first
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        // Airdrop tokens to receiver
        uint256 amount = 1000 * 10 ** decimals;
        airdrop(asset, address(receiver), amount);

        // Deposit tokens
        receiver.deposit(address(asset));

        // Setup recipients and values
        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = keeper;

        uint256[] memory values = new uint256[](2);
        values[0] = amount / 2;
        values[1] = amount / 2;

        // Disperse tokens
        vm.prank(management);
        receiver.disperse(address(asset), recipients, values);

        // Check balances
        assertEq(preDepositVault.balanceOf(user), amount / 2, "!user balance");
        assertEq(
            preDepositVault.balanceOf(keeper),
            amount / 2,
            "!keeper balance"
        );
        assertEq(
            preDepositVault.balanceOf(address(receiver)),
            0,
            "!receiver balance"
        );
    }

    function test_disperse_andDeposit() public {
        // Set vault first
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        // Airdrop tokens to receiver
        uint256 amount = 1000 * 10 ** decimals;
        airdrop(asset, address(receiver), amount);

        // Setup recipients and values
        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = keeper;

        uint256[] memory values = new uint256[](2);
        values[0] = amount / 2;
        values[1] = amount / 2;

        // Disperse tokens
        vm.prank(management);
        receiver.disperse(address(asset), recipients, values);

        // Check balances
        assertEq(preDepositVault.balanceOf(user), amount / 2, "!user balance");
        assertEq(
            preDepositVault.balanceOf(keeper),
            amount / 2,
            "!keeper balance"
        );
        assertEq(
            preDepositVault.balanceOf(address(receiver)),
            0,
            "!receiver balance"
        );
    }

    function test_RevertWhen_DispersingWithoutVault() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user;

        uint256[] memory values = new uint256[](1);
        values[0] = 1000 * 10 ** decimals;

        vm.prank(management);
        vm.expectRevert("Vault not found");
        receiver.disperse(address(asset), recipients, values);
    }

    function test_RevertWhen_DispersingInvalidLength() public {
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = keeper;

        uint256[] memory values = new uint256[](1);
        values[0] = 1000 * 10 ** decimals;

        vm.prank(management);
        vm.expectRevert("Invalid length");
        receiver.disperse(address(asset), recipients, values);
    }

    function test_RevertWhen_NonGovernanceDisperses() public {
        vm.prank(management);
        receiver.setVault(address(asset), address(preDepositVault));

        address[] memory recipients = new address[](1);
        recipients[0] = user;

        uint256[] memory values = new uint256[](1);
        values[0] = 1000 * 10 ** decimals;

        vm.prank(user);
        vm.expectRevert("!governance");
        receiver.disperse(address(asset), recipients, values);
    }
}
