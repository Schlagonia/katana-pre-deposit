// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface, IVault} from "./utils/Setup.sol";

contract OperationTest is Setup {
    event PreDepositDeployed(address indexed asset, address indexed vault);
    event VaultSet(address indexed asset, address indexed vault);
    event DepositProcessed(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 originChainId
    );

    function setUp() public virtual override {
        super.setUp();
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into vault
        airdrop(asset, user, _amount);

        vm.prank(user);
        asset.approve(address(depositRelayer), _amount);

        vm.prank(user);
        depositRelayer.deposit(address(asset), _amount);

        assertEq(preDepositVault.totalAssets(), _amount, "!totalAssets");

        assertEq(preDepositVault.balanceOf(user), 0, "!balance");
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            _amount,
            "!depositRelayer balance"
        );

        vm.prank(chad);
        preDepositVault.update_debt(address(yearnVault), _amount);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = preDepositVault.process_report(
            address(yearnVault)
        );

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // Make sure accountant takes 100% of profit
        assertGt(
            preDepositVault.balanceOf(address(depositRelayer.ACCOUNTANT())),
            0,
            "!accountant balance"
        );

        skip(preDepositVault.profitMaxUnlockTime());

        assertEq(
            preDepositVault.pricePerShare(),
            10 ** decimals,
            "!pricePerShare"
        );

        uint256 balanceBefore = asset.balanceOf(user);

        assertEq(preDepositVault.maxWithdraw(user), 0, "!maxWithdraw");
    }

    function test_constructor() public {
        // Test PreDepositFactory constructor
        assertEq(preDepositFactory.governance(), management);
        assertEq(preDepositFactory.TARGET_NETWORK_ID(), targetNetworkId);
        assertEq(
            address(preDepositFactory.DEPOSIT_RELAYER()),
            address(depositRelayer)
        );
        assertEq(
            address(preDepositFactory.SHARE_RECEIVER()),
            address(depositRelayer.SHARE_RECEIVER())
        );

        // Test DepositRelayer constructor
        assertEq(depositRelayer.governance(), management);
        assertEq(depositRelayer.ACROSS_BRIDGE(), acrossBridge);
        assertEq(
            depositRelayer.PRE_DEPOSIT_FACTORY(),
            address(preDepositFactory)
        );

        // Test ShareReceiver constructor
        assertEq(shareReceiver.DEPOSIT_RELAYER(), address(depositRelayer));
    }

    function test_deployPreDeposit() public {
        address newAsset = tokenAddrs["DAI"];
        address newYearnVault = yearnVaults[newAsset];
        address newStbVault = deployNewVault(newAsset);

        vm.startPrank(management);

        vm.expectEmit(true, false, false, false);
        emit PreDepositDeployed(newAsset, address(0));

        address newVault = preDepositFactory.deployPreDeposit(
            newAsset,
            newYearnVault,
            newStbVault
        );

        assertEq(preDepositFactory.preDepositVault(newAsset), newVault);
        assertEq(depositRelayer.assetToVault(newAsset), newVault);

        vm.stopPrank();
    }

    function test_depositRelayer_setVault() public {
        address newAsset = tokenAddrs["DAI"];
        address newVault = deployNewVault(newAsset);

        vm.startPrank(management);

        vm.expectEmit(true, true, false, true);
        emit VaultSet(newAsset, newVault);

        depositRelayer.setVault(newAsset, newVault);
        assertEq(depositRelayer.assetToVault(newAsset), newVault);

        vm.stopPrank();
    }

    function test_depositRelayer_deposit() public {
        uint256 depositAmount = 1000 * 10 ** decimals;

        // Setup user with tokens
        airdrop(asset, user, depositAmount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            block.chainid
        );

        depositRelayer.deposit(address(asset), depositAmount);

        // Check deposited amount is tracked
        assertEq(shareReceiver.deposited(address(asset), user), depositAmount);

        vm.stopPrank();
    }

    function test_depositRelayer_handleV3AcrossMessage() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 originChainId = 137; // Example chain ID

        // Setup relayer with tokens
        airdrop(asset, address(depositRelayer), depositAmount);

        bytes memory message = abi.encode(user, originChainId);

        vm.prank(acrossBridge);
        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            originChainId
        );

        depositRelayer.handleV3AcrossMessage(
            address(asset),
            depositAmount,
            address(0), // relayer address (unused)
            message
        );

        // Check deposited amount is tracked
        assertEq(shareReceiver.deposited(address(asset), user), depositAmount);
    }
    /**
    function test_shareReceiver_depositLimits() public {
        // Should allow max deposits to ShareReceiver
        assertEq(
            shareReceiver.available_deposit_limit(address(shareReceiver)),
            type(uint256).max
        );
        assertEq(
            preDepositVault.maxDeposit(address(shareReceiver)),
            type(uint256).max
        );

        // Should prevent deposits to other addresses
        assertEq(shareReceiver.available_deposit_limit(address(this)), 0);
        assertEq(preDepositVault.maxDeposit(address(this)), 0);
    }

    function test_shareReceiver_withdrawLimits() public {
        address[] memory strategies;

        // Should prevent all withdrawals
        assertEq(
            shareReceiver.available_withdraw_limit(
                address(this),
                100,
                strategies
            ),
            0
        );
        assertEq(preDepositVault.maxWithdraw(address(this)), 0);
    }
    */

    function test_shareReceiver_pullShares() public {
        uint256 amount = 1000 * 10 ** decimals;

        // Setup ShareReceiver with tokens
        airdrop(asset, address(shareReceiver), amount);

        // Only governance should be able to pull shares
        vm.expectRevert("!governance");
        shareReceiver.pullShares(address(asset), amount);

        uint256 balanceBefore = asset.balanceOf(management);

        vm.prank(management);
        shareReceiver.pullShares(address(asset), amount);

        assertEq(asset.balanceOf(management), balanceBefore + amount);
    }

    function test_RevertWhen_NonGovernanceDeploysPreDeposit() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        preDepositFactory.deployPreDeposit(
            address(asset),
            address(yearnVault),
            address(stbVault)
        );
    }

    function test_RevertWhen_NonFactorySetVault() public {
        vm.prank(user);
        vm.expectRevert("Invalid caller");
        depositRelayer.setVault(address(asset), address(preDepositVault));
    }

    function test_RevertWhen_NonBridgeHandlesMessage() public {
        vm.prank(user);
        vm.expectRevert("Invalid caller");
        depositRelayer.handleV3AcrossMessage(
            address(asset),
            100,
            address(0),
            ""
        );
    }

    function test_RevertWhen_DepositingInvalidAmount() public {
        vm.prank(user);
        vm.expectRevert("Invalid amount");
        depositRelayer.deposit(address(asset), 0);
    }

    function test_RevertWhen_DepositingInvalidAsset() public {
        vm.prank(user);
        vm.expectRevert("Vault not set");
        depositRelayer.deposit(address(0), 100);
    }

    function test_depositRelayer_rescue() public {
        uint256 amount = 1000 * 10 ** decimals;
        airdrop(asset, address(depositRelayer), amount);

        uint256 balanceBefore = asset.balanceOf(management);

        vm.prank(management);
        depositRelayer.rescue(address(asset));

        assertEq(asset.balanceOf(management), balanceBefore + amount);
    }

    function testFuzz_depositRelayer_deposit(uint256 amount) public {
        // Bound amount between min and max fuzz amounts
        amount = bound(amount, minFuzzAmount, maxFuzzAmount);

        airdrop(asset, user, amount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), amount);
        depositRelayer.deposit(address(asset), amount);

        assertEq(shareReceiver.deposited(address(asset), user), amount);
        assertEq(preDepositVault.balanceOf(user), 0);
        assertEq(preDepositVault.balanceOf(address(shareReceiver)), amount);
        vm.stopPrank();
    }
}
