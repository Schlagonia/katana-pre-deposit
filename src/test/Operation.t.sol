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
        uint256 originChainId,
        address referral
    );
    event DepositCapSet(address indexed asset, uint256 indexed cap);

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
            preDepositVault.balanceOf(address(preDepositFactory.ACCOUNTANT())),
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
        assertEq(depositRelayer.governance(), management);
        assertEq(preDepositFactory.TARGET_NETWORK_ID(), targetNetworkId);
        assertEq(
            address(preDepositFactory.DEPOSIT_RELAYER()),
            address(depositRelayer)
        );

        // Test DepositRelayer constructor
        assertEq(depositRelayer.acrossBridge(), acrossBridge);
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

        assertEq(depositRelayer.preDepositVault(newAsset), newVault);

        vm.stopPrank();
    }

    function test_preDepositFactory_setVault() public {
        address newAsset = tokenAddrs["DAI"];
        address newVault = deployNewVault(newAsset);

        vm.startPrank(management);

        vm.expectEmit(true, true, false, true);
        emit VaultSet(newAsset, newVault);

        depositRelayer.setVault(newAsset, newVault);
        assertEq(depositRelayer.preDepositVault(newAsset), newVault);

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
            block.chainid,
            address(0)
        );

        depositRelayer.deposit(address(asset), depositAmount);

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(address(asset), user), depositAmount);

        vm.stopPrank();
    }

    function test_depositRelayer_handleV3AcrossMessage() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 originChainId = 137; // Example chain ID

        // Setup relayer with tokens
        airdrop(asset, address(depositRelayer), depositAmount);

        bytes memory message = abi.encode(user, originChainId, address(0));

        vm.prank(acrossBridge);
        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            originChainId,
            address(0)
        );

        depositRelayer.handleV3AcrossMessage(
            address(asset),
            depositAmount,
            address(0), // relayer address (unused)
            message
        );

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(address(asset), user), depositAmount);
    }

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
        vm.expectRevert("!governance");
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

        assertEq(depositRelayer.deposited(address(asset), user), amount);
        assertEq(preDepositVault.balanceOf(user), 0);
        assertEq(preDepositVault.balanceOf(address(shareReceiver)), amount);
        vm.stopPrank();
    }

    function test_depositRelayer_deposit_withReferral() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        address referral = address(0xdead);

        // Setup user with tokens
        airdrop(asset, user, depositAmount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            block.chainid,
            referral
        );

        depositRelayer.deposit(address(asset), depositAmount, referral);

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(address(asset), user), depositAmount);
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            depositAmount
        );

        vm.stopPrank();
    }

    function test_depositRelayer_handleV3AcrossMessage_withReferral() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 originChainId = 137; // Example chain ID
        address referral = address(0xdead);

        // Setup relayer with tokens
        airdrop(asset, address(depositRelayer), depositAmount);

        bytes memory message = abi.encode(user, originChainId, referral);

        vm.prank(acrossBridge);
        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            originChainId,
            referral
        );

        depositRelayer.handleV3AcrossMessage(
            address(asset),
            depositAmount,
            address(0), // relayer address (unused)
            message
        );

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(address(asset), user), depositAmount);
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            depositAmount
        );
    }

    function testFuzz_depositRelayer_deposit_withReferral(
        uint256 amount,
        address referral
    ) public {
        vm.assume(amount > minFuzzAmount && amount < maxFuzzAmount);

        airdrop(asset, user, amount);

        vm.startPrank(user);
        asset.approve(address(depositRelayer), amount);
        depositRelayer.deposit(address(asset), amount, referral);

        assertEq(depositRelayer.deposited(address(asset), user), amount);
        assertEq(preDepositVault.balanceOf(user), 0);
        assertEq(preDepositVault.balanceOf(address(shareReceiver)), amount);
        vm.stopPrank();
    }

    function test_depositCaps() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 depositCap = 2000 * 10 ** decimals;

        // Set deposit cap
        vm.prank(management);
        depositRelayer.setDepositCap(address(asset), depositCap);

        // Verify max deposit
        assertEq(depositRelayer.maxDeposit(address(asset)), depositCap);

        // First deposit should succeed
        airdrop(asset, user, depositAmount);
        vm.startPrank(user);
        asset.approve(address(depositRelayer), depositAmount);
        depositRelayer.deposit(address(asset), depositAmount);
        vm.stopPrank();

        // Verify deposit was tracked
        assertEq(depositRelayer.totalDeposited(address(asset)), depositAmount);
        assertEq(
            depositRelayer.maxDeposit(address(asset)),
            depositCap - depositAmount
        );

        // Second deposit that would exceed cap should fail
        uint256 secondDeposit = depositCap;
        airdrop(asset, user, secondDeposit);
        vm.startPrank(user);
        asset.approve(address(depositRelayer), secondDeposit);
        vm.expectRevert("Deposit cap exceeded");
        depositRelayer.deposit(address(asset), secondDeposit);
        vm.stopPrank();
    }

    function test_depositCaps_acrossMessage() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 depositCap = 2000 * 10 ** decimals;
        uint256 originChainId = 137;

        // Set deposit cap
        vm.prank(management);
        depositRelayer.setDepositCap(address(asset), depositCap);

        // First deposit should succeed
        airdrop(asset, address(depositRelayer), depositAmount);
        bytes memory message = abi.encode(user, originChainId, address(0));
        vm.prank(acrossBridge);
        depositRelayer.handleV3AcrossMessage(
            address(asset),
            depositAmount,
            address(0),
            message
        );

        // Verify deposit was tracked
        assertEq(depositRelayer.totalDeposited(address(asset)), depositAmount);
        assertEq(
            depositRelayer.maxDeposit(address(asset)),
            depositCap - depositAmount
        );

        // Second deposit that would exceed cap should fail
        uint256 secondDeposit = depositCap;
        airdrop(asset, address(depositRelayer), secondDeposit);
        message = abi.encode(user, originChainId, address(0));
        vm.prank(acrossBridge);
        vm.expectRevert("Deposit cap exceeded");
        depositRelayer.handleV3AcrossMessage(
            address(asset),
            secondDeposit,
            address(0),
            message
        );
    }

    function test_RevertWhen_NonGovernanceSetsCap() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        depositRelayer.setDepositCap(address(asset), 1000);
    }

    function test_setDepositCap() public {
        uint256 newCap = 1000 * 10 ** decimals;

        vm.startPrank(management);

        vm.expectEmit(true, false, false, true);
        emit DepositCapSet(address(asset), newCap);

        depositRelayer.setDepositCap(address(asset), newCap);
        assertEq(depositRelayer.depositCap(address(asset)), newCap);
        assertEq(depositRelayer.maxDeposit(address(asset)), newCap);

        vm.stopPrank();
    }

    function testFuzz_depositCaps(
        uint256 cap,
        uint256 firstDeposit,
        uint256 secondDeposit
    ) public {
        // Bound the values to reasonable ranges
        cap = bound(cap, minFuzzAmount, maxFuzzAmount);
        firstDeposit = bound(firstDeposit, minFuzzAmount, cap);
        secondDeposit = bound(secondDeposit, 1, maxFuzzAmount);

        // Set deposit cap
        vm.prank(management);
        depositRelayer.setDepositCap(address(asset), cap);

        // First deposit
        airdrop(asset, user, firstDeposit);
        vm.startPrank(user);
        asset.approve(address(depositRelayer), firstDeposit);
        depositRelayer.deposit(address(asset), firstDeposit);
        vm.stopPrank();

        // Verify first deposit
        assertEq(depositRelayer.totalDeposited(address(asset)), firstDeposit);
        assertEq(depositRelayer.maxDeposit(address(asset)), cap - firstDeposit);

        // Second deposit
        if (secondDeposit + firstDeposit > cap) {
            // Should fail if it would exceed cap
            airdrop(asset, user, secondDeposit);
            vm.startPrank(user);
            asset.approve(address(depositRelayer), secondDeposit);
            vm.expectRevert("Deposit cap exceeded");
            depositRelayer.deposit(address(asset), secondDeposit);
            vm.stopPrank();
        } else {
            // Should succeed if within cap
            airdrop(asset, user, secondDeposit);
            vm.startPrank(user);
            asset.approve(address(depositRelayer), secondDeposit);
            depositRelayer.deposit(address(asset), secondDeposit);
            vm.stopPrank();

            assertEq(
                depositRelayer.totalDeposited(address(asset)),
                firstDeposit + secondDeposit
            );
        }
    }

    function test_depositRelayer_depositEth() public {
        uint256 depositAmount = 1 ether;

        // Set WETH vault
        address wethVault = newPreDepositVault(weth);

        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            weth,
            user,
            depositAmount,
            block.chainid,
            address(0)
        );

        vm.deal(user, depositAmount);
        vm.prank(user);
        depositRelayer.depositEth{value: depositAmount}();

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(weth, user), depositAmount);
        assertEq(ERC20(weth).balanceOf(address(depositRelayer)), 0);
        assertEq(
            IVault(wethVault).balanceOf(address(shareReceiver)),
            depositAmount
        );
    }

    function test_depositRelayer_depositEth_withReferral() public {
        uint256 depositAmount = 1 ether;
        address referral = address(0xdead);

        // Set WETH vault
        address wethVault = newPreDepositVault(weth);

        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            weth,
            user,
            depositAmount,
            block.chainid,
            referral
        );

        vm.deal(user, depositAmount);
        vm.prank(user);
        depositRelayer.depositEth{value: depositAmount}(referral);

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(weth, user), depositAmount);
        assertEq(ERC20(weth).balanceOf(address(depositRelayer)), 0);
        assertEq(
            IVault(wethVault).balanceOf(address(shareReceiver)),
            depositAmount
        );
    }

    function test_RevertWhen_DepositingEthWithoutVault() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert("Vault not set");
        depositRelayer.depositEth{value: 1 ether}();
    }

    function test_RevertWhen_DepositingZeroEth() public {
        newPreDepositVault(weth);
        vm.prank(user);
        vm.expectRevert("Invalid amount");
        depositRelayer.depositEth{value: 0}();
    }

    function test_depositRelayer_handleRelayLinkDeposit() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 originChainId = 137; // Example chain ID
        address referral = address(0xdead);

        // Setup relayer with tokens
        airdrop(asset, address(depositRelayer), depositAmount);

        vm.prank(relayLinkBridge);
        vm.expectEmit(true, true, true, true);
        emit DepositProcessed(
            address(asset),
            user,
            depositAmount,
            originChainId,
            referral
        );

        depositRelayer.handleRelayLinkDeposit(
            address(asset),
            depositAmount,
            user,
            originChainId,
            referral
        );

        // Check deposited amount is tracked
        assertEq(depositRelayer.deposited(address(asset), user), depositAmount);
        assertEq(
            preDepositVault.balanceOf(address(shareReceiver)),
            depositAmount
        );
    }

    function test_RevertWhen_NonRelayLinkBridgeHandlesDeposit() public {
        vm.prank(user);
        vm.expectRevert("Invalid caller");
        depositRelayer.handleRelayLinkDeposit(
            address(asset),
            100,
            user,
            1,
            address(0)
        );
    }

    function test_depositCaps_withEth() public {
        uint256 depositAmount = 1 ether;
        uint256 depositCap = 2 ether;

        // Set WETH vault

        address wethVault = newPreDepositVault(weth);

        vm.startPrank(management);
        depositRelayer.setDepositCap(weth, depositCap);
        vm.stopPrank();

        // First deposit should succeed
        vm.deal(user, depositAmount);
        vm.prank(user);
        depositRelayer.depositEth{value: depositAmount}();

        // Verify deposit was tracked
        assertEq(depositRelayer.totalDeposited(weth), depositAmount);
        assertEq(depositRelayer.maxDeposit(weth), depositCap - depositAmount);

        // Second deposit that would exceed cap should fail
        uint256 secondDeposit = depositCap;
        vm.deal(user, secondDeposit);
        vm.prank(user);
        vm.expectRevert("Deposit cap exceeded");
        depositRelayer.depositEth{value: secondDeposit}();
    }

    function testFuzz_depositRelayer_depositEth(
        uint256 amount,
        address referral
    ) public {
        // Bound amount between 0.01 ETH and 100 ETH
        amount = bound(amount, 0.01 ether, 100 ether);

        // Set WETH vault
        address wethVault = newPreDepositVault(weth);

        vm.deal(user, amount);
        vm.prank(user);
        depositRelayer.depositEth{value: amount}(referral);

        assertEq(depositRelayer.deposited(weth, user), amount);
        assertEq(ERC20(weth).balanceOf(address(depositRelayer)), 0);
        assertEq(IVault(wethVault).balanceOf(address(shareReceiver)), amount);
    }

    function test_depositRelayer_handleRelayLinkDeposit_withCaps() public {
        uint256 depositAmount = 1000 * 10 ** decimals;
        uint256 depositCap = 2000 * 10 ** decimals;
        uint256 originChainId = 137;

        // Set deposit cap
        vm.prank(management);
        depositRelayer.setDepositCap(address(asset), depositCap);

        // First deposit should succeed
        airdrop(asset, address(depositRelayer), depositAmount);
        vm.prank(relayLinkBridge);
        depositRelayer.handleRelayLinkDeposit(
            address(asset),
            depositAmount,
            user,
            originChainId,
            address(0)
        );

        // Verify deposit was tracked
        assertEq(depositRelayer.totalDeposited(address(asset)), depositAmount);
        assertEq(
            depositRelayer.maxDeposit(address(asset)),
            depositCap - depositAmount
        );

        // Second deposit that would exceed cap should fail
        uint256 secondDeposit = depositCap;
        airdrop(asset, address(depositRelayer), secondDeposit);
        vm.prank(relayLinkBridge);
        vm.expectRevert("Deposit cap exceeded");
        depositRelayer.handleRelayLinkDeposit(
            address(asset),
            secondDeposit,
            user,
            originChainId,
            address(0)
        );
    }
}
