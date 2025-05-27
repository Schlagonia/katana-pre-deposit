// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface, IVault, STBDepositor} from "./utils/Setup.sol";
import {IPolygonZkEVMBridge} from "../interfaces/IPolygonZkEVMBridge.sol";

contract BridgeTest is Setup {
    event BridgeEvent(
        uint8 leafType,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes metadata,
        uint32 depositCount
    );

    address public constant ZKEVM_BRIDGE =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;
    address public constant KATANA_RECEIVER =
        0x1234567890123456789012345678901234567890; // Example receiver on Katana

    function setUp() public override {
        super.setUp();

        // Set the Katana receiver address in the STB Depositor
        vm.prank(management);
        strategy.setKatanaReceiver(KATANA_RECEIVER);
    }

    function test_fullBridgeFlow(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // ======= Step 1: Initial deposit into preDepositVault through depositRelayer =======
        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), _amount);
        depositRelayer.deposit(address(asset), _amount);
        vm.stopPrank();

        // Verify initial deposit
        assertEq(preDepositVault.totalAssets(), _amount, "!totalAssets");
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            _amount,
            "!shareReceiver balance"
        );

        // ======= Step 2: Move all funds to STBDepositor strategy =======

        // Then, move all funds to STBDepositor
        vm.prank(chad);
        preDepositVault.update_debt(address(strategy), _amount);

        // Verify funds moved to STBDepositor
        assertApproxEqAbs(
            preDepositVault.strategies(address(strategy)).current_debt,
            _amount,
            1,
            "!stbDepositor debt"
        );

        // ======= Step 3: Bridge funds using STBDepositor =======
        // Store balances before bridge
        uint256 vaultSharesBefore = ERC20(address(stbVault)).balanceOf(
            address(strategy)
        );

        bytes memory metadata = IPolygonZkEVMBridge(ZKEVM_BRIDGE)
            .getTokenMetadata(address(stbVault));
        uint256 depositCount = IPolygonZkEVMBridge(ZKEVM_BRIDGE).depositCount();
        vm.expectEmit(true, true, true, true, address(ZKEVM_BRIDGE));
        emit BridgeEvent(
            0,
            uint32(0),
            address(stbVault),
            uint32(targetNetworkId),
            KATANA_RECEIVER,
            vaultSharesBefore,
            metadata,
            uint32(depositCount)
        );
        // Bridge the funds
        vm.prank(management);
        strategy.bridgeFunds(vaultSharesBefore);

        // Verify STBDepositor no longer holds any vault shares
        assertEq(
            ERC20(address(stbVault)).balanceOf(address(strategy)),
            0,
            "!shares bridged"
        );
    }

    function test_partialBridgeFlow(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // ======= Step 1: Initial deposit into preDepositVault through depositRelayer =======
        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), _amount);
        depositRelayer.deposit(address(asset), _amount);
        vm.stopPrank();

        // Verify initial deposit
        assertEq(preDepositVault.totalAssets(), _amount, "!totalAssets");
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            _amount,
            "!shareReceiver balance"
        );

        // ======= Step 2: Move all funds to STBDepositor strategy =======

        // Then, move all funds to STBDepositor
        vm.prank(chad);
        preDepositVault.update_debt(address(strategy), _amount);

        // Verify funds moved to STBDepositor
        assertApproxEqAbs(
            preDepositVault.strategies(address(strategy)).current_debt,
            _amount,
            1,
            "!stbDepositor debt"
        );

        // ======= Step 3: Bridge funds using STBDepositor =======
        // Store balances before bridge
        uint256 vaultSharesBefore = ERC20(address(stbVault)).balanceOf(
            address(strategy)
        );

        uint256 sharesToBridge = vaultSharesBefore / 2;

        bytes memory metadata = IPolygonZkEVMBridge(ZKEVM_BRIDGE)
            .getTokenMetadata(address(stbVault));
        uint256 depositCount = IPolygonZkEVMBridge(ZKEVM_BRIDGE).depositCount();
        vm.expectEmit(true, true, true, true, address(ZKEVM_BRIDGE));
        emit BridgeEvent(
            0,
            uint32(0),
            address(stbVault),
            uint32(targetNetworkId),
            KATANA_RECEIVER,
            sharesToBridge,
            metadata,
            uint32(depositCount)
        );
        // Bridge the funds
        vm.prank(management);
        strategy.bridgeFunds(sharesToBridge);

        // Verify STBDepositor no longer holds any vault shares
        assertEq(
            ERC20(address(stbVault)).balanceOf(address(strategy)),
            _amount - sharesToBridge,
            "!shares bridged"
        );
    }

    function test_RevertWhen_BridgingWithoutKatanaReceiver() public {
        uint256 amount = 1000 * 10 ** decimals;

        strategy = IStrategyInterface(
            address(
                new STBDepositor(
                    address(asset),
                    "STB Depositor",
                    address(stbVault),
                    address(preDepositVault),
                    address(preDepositFactory)
                )
            )
        );

        strategy.setPendingManagement(management);
        vm.prank(management);
        strategy.acceptManagement();

        vm.startPrank(chad);
        preDepositVault.add_strategy(address(strategy));
        preDepositVault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );
        vm.stopPrank();

        // Setup initial deposit
        airdrop(asset, user, amount);
        vm.startPrank(user);
        asset.approve(address(depositRelayer), amount);
        depositRelayer.deposit(address(asset), amount);
        vm.stopPrank();

        // Move funds to STBDepositor
        vm.startPrank(chad);
        preDepositVault.update_debt(address(strategy), amount);
        vm.stopPrank();

        // Try to bridge without Katana receiver set
        vm.prank(management);
        vm.expectRevert("KATANA RECEIVER NOT SET");
        strategy.bridgeFunds(amount);
    }

    function test_RevertWhen_NonManagementBridges() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.bridgeFunds(0);
    }

    function test_RevertWhen_Bridge_zeroAmount() public {
        // Set Katana receiver
        vm.prank(management);
        strategy.setKatanaReceiver(KATANA_RECEIVER);

        // Try to bridge with no funds
        vm.prank(management);
        vm.expectRevert("!shares");
        strategy.bridgeFunds(0);
    }

    function test_setKatanaReceiver() public {
        vm.prank(management);
        strategy.setKatanaReceiver(KATANA_RECEIVER);

        assertEq(strategy.katanaReceiver(), KATANA_RECEIVER);
    }

    function test_RevertWhen_SettingZeroAddressReceiver() public {
        vm.prank(management);
        vm.expectRevert("ZERO ADDRESS");
        strategy.setKatanaReceiver(address(0));
    }

    function test_RevertWhen_NonManagementSetsReceiver() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setKatanaReceiver(KATANA_RECEIVER);
    }
}
