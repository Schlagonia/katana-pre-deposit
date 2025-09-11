// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Setup, ERC20, IVault} from "./utils/Setup.sol";
import {AccountantProxy} from "../AccountantProxy.sol";

interface IAccountantFull {
    function turnOffHealthCheck(address vault, address strategy) external;
    function addVault(address vault) external;
    function setFeeRecipient(address newFeeRecipient) external;
    function feeManager() external view returns (address);
    function feeRecipient() external view returns (address);
    function vaultManager() external view returns (address);
    function setFutureFeeManager(address _futureFeeManager) external;
    function acceptFeeManager() external;
    function updateDefaultConfig(
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) external;
}

interface IAccountantFactory {
    function newAccountant(
        address feeManager,
        address feeRecipient
    ) external returns (address);
}

contract AccountantProxyTest is Setup {
    event ReporterSet(address indexed reporter, bool authorized);

    AccountantProxy public accountantProxy;
    IAccountantFull public accountant;
    address public reporter = address(0x1234);
    address public nonReporter = address(0x5678);
    address constant ACCOUNTANT_FACTORY =
        0xF728f839796a399ACc2823c1e5591F05a31c32d1;

    function setUp() public virtual override {
        super.setUp();

        // Deploy a new accountant from the factory
        // AccountantProxy will be the fee manager, management will be the fee recipient
        address newAccountant = IAccountantFactory(ACCOUNTANT_FACTORY)
            .newAccountant(
                management, // fee manager (temporary, will transfer to proxy)
                management // fee recipient
            );
        accountant = IAccountantFull(newAccountant);

        // Deploy AccountantProxy with management as governance
        accountantProxy = new AccountantProxy(address(accountant), management);

        // Transfer fee manager role to the proxy
        vm.prank(management); // management is the initial fee manager
        accountant.setFutureFeeManager(address(accountantProxy));

        vm.prank(address(management));
        IAccountantFull(address(accountantProxy)).acceptFeeManager();

        // Add the preDepositVault to the accountant
        vm.prank(management);
        IAccountantFull(address(accountantProxy)).addVault(
            address(preDepositVault)
        );

        // Set the new accountant on the vault
        vm.prank(chad);
        preDepositVault.set_accountant(address(accountant));

        // Give the accountant proxy permission to report
        vm.prank(address(yearnRoleManager));
        preDepositVault.add_role(address(accountantProxy), 32); // REPORTING_MANAGER role = 32
    }

    function test_constructor() public {
        assertEq(accountantProxy.ACCOUNTANT(), address(accountant));
        assertEq(accountantProxy.governance(), management);
    }

    function test_setReporter() public {
        // Test adding a reporter
        vm.expectEmit(true, false, false, true);
        emit ReporterSet(reporter, true);

        vm.prank(management);
        accountantProxy.setReporter(reporter, true);

        assertTrue(accountantProxy.canReport(reporter));

        // Test removing a reporter
        vm.expectEmit(true, false, false, true);
        emit ReporterSet(reporter, false);

        vm.prank(management);
        accountantProxy.setReporter(reporter, false);

        assertFalse(accountantProxy.canReport(reporter));
    }

    function test_setReporter_revertConditions() public {
        // Test zero address
        vm.prank(management);
        vm.expectRevert("zero address");
        accountantProxy.setReporter(address(0), true);

        // Test already set
        vm.prank(management);
        accountantProxy.setReporter(reporter, true);

        vm.prank(management);
        vm.expectRevert("already set");
        accountantProxy.setReporter(reporter, true);

        // Test non-governance
        vm.expectRevert("!governance");
        accountantProxy.setReporter(reporter, false);
    }

    function test_reportOnSelf() public {
        // Setup: Add reporter and airdrop tokens to vault
        vm.prank(management);
        accountantProxy.setReporter(reporter, true);

        uint256 airdropAmount = 1000 * 10 ** decimals;

        // Airdrop tokens directly to the vault
        airdrop(asset, address(preDepositVault), airdropAmount);

        // Store initial state
        uint256 initialTotalAssets = preDepositVault.totalAssets();
        uint256 initialTotalIdle = preDepositVault.totalIdle();
        uint256 initialPPS = preDepositVault.pricePerShare();
        uint256 initialFees = preDepositVault.balanceOf(address(accountant));

        // Report on self
        vm.prank(reporter);
        (uint256 gain, uint256 loss) = accountantProxy.reportOnSelf(
            address(preDepositVault)
        );

        // Verify results
        assertEq(gain, airdropAmount, "gain should equal airdrop amount");
        assertEq(loss, 0, "loss should be 0");
        assertEq(
            preDepositVault.pricePerShare(),
            initialPPS,
            "PPS should not change"
        );
        assertEq(
            preDepositVault.totalIdle(),
            initialTotalIdle + airdropAmount,
            "totalIdle should increase by gain"
        );
        assertEq(
            preDepositVault.totalAssets(),
            initialTotalAssets + airdropAmount,
            "totalAssets should increase by gain"
        );
        assertEq(
            preDepositVault.balanceOf(address(accountant)),
            initialFees,
            "accountant balance should not change"
        );
    }

    function test_reportOnSelf_revertNoGain() public {
        vm.prank(management);
        accountantProxy.setReporter(reporter, true);

        // Try to report when there's no gain
        vm.prank(reporter);
        vm.expectRevert("no gain");
        accountantProxy.reportOnSelf(address(preDepositVault));
    }

    function test_reportOnSelf_revertUnauthorized() public {
        // Try to report without being authorized
        vm.expectRevert("!authorized");
        accountantProxy.reportOnSelf(address(preDepositVault));
    }

    function test_fallback_governance() public {
        // Test that governance can call fee manager functions through fallback
        address newFeeRecipient = address(0x9999);

        vm.prank(management);
        IAccountantFull(address(accountantProxy)).setFeeRecipient(
            newFeeRecipient
        );

        assertEq(
            IAccountantFull(address(accountant)).feeRecipient(),
            newFeeRecipient,
            "fee recipient should be updated"
        );
    }

    function test_fallback_revertNonGovernance() public {
        // Test that non-governance cannot call through fallback
        vm.expectRevert("!governance");
        IAccountantFull(address(accountantProxy)).setFeeRecipient(
            address(0x9999)
        );
    }

    function test_fallback_updateDefaultConfig() public {
        // Test updating default config through fallback
        vm.prank(management);
        IAccountantFull(address(accountantProxy)).updateDefaultConfig(
            100, // management fee (1%)
            1000, // performance fee (10%)
            0, // refund ratio
            5000, // max fee (50%)
            10000, // max gain (100%)
            10000 // max loss (100%)
        );
    }

    function test_reportOnSelf_withFuzzedAmount(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup reporter
        vm.prank(management);
        accountantProxy.setReporter(reporter, true);

        // Airdrop tokens to vault
        airdrop(asset, address(preDepositVault), _amount);

        // Store initial state
        uint256 initialPPS = preDepositVault.pricePerShare();

        // Report on self
        vm.prank(reporter);
        (uint256 gain, uint256 loss) = accountantProxy.reportOnSelf(
            address(preDepositVault)
        );

        // Verify
        assertEq(gain, _amount);
        assertEq(loss, 0);
        assertEq(preDepositVault.pricePerShare(), initialPPS);
    }

    function test_multipleReporters() public {
        address reporter2 = address(0x2222);
        address reporter3 = address(0x3333);

        // Add multiple reporters
        vm.startPrank(management);
        accountantProxy.setReporter(reporter, true);
        accountantProxy.setReporter(reporter2, true);
        accountantProxy.setReporter(reporter3, true);
        vm.stopPrank();

        // Verify all can report
        assertTrue(accountantProxy.canReport(reporter));
        assertTrue(accountantProxy.canReport(reporter2));
        assertTrue(accountantProxy.canReport(reporter3));

        // Remove one
        vm.prank(management);
        accountantProxy.setReporter(reporter2, false);

        // Verify removal
        assertTrue(accountantProxy.canReport(reporter));
        assertFalse(accountantProxy.canReport(reporter2));
        assertTrue(accountantProxy.canReport(reporter3));
    }

    function test_governanceTransfer() public {
        address newGovernance = address(0x7777);

        // Transfer governance
        vm.prank(management);
        accountantProxy.transferGovernance(newGovernance);

        assertEq(accountantProxy.governance(), newGovernance);

        // Old governance cannot call functions
        vm.prank(management);
        vm.expectRevert("!governance");
        accountantProxy.setReporter(reporter, true);

        // New governance can
        vm.prank(newGovernance);
        accountantProxy.setReporter(reporter, true);
        assertTrue(accountantProxy.canReport(reporter));
    }
}
