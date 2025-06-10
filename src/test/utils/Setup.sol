// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {STBDepositor} from "../../STBDepositor.sol";
import {ShareReceiver} from "../../ShareReceiver.sol";
import {DepositRelayer} from "../../DepositRelayer.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IYearnRoleManager} from "../../interfaces/IYearnRoleManager.sol";

import {PreDepositFactory} from "../../PreDepositFactory.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    IVaultFactory public constant vaultFactory =
        IVaultFactory(0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F);

    ShareReceiver public shareReceiver;

    DepositRelayer public depositRelayer;

    PreDepositFactory public preDepositFactory;

    IVault public preDepositVault;

    address public acrossBridge = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;

    address public relayLinkBridge = 0xeeeeee9eC4769A09a76A83C7bC42b185872860eE;

    IVault public stbVault;

    IVault public yearnVault;

    IYearnRoleManager public yearnRoleManager =
        IYearnRoleManager(0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41);

    address public weth;

    uint32 public targetNetworkId = 1;

    address public chad;

    mapping(string => address) public tokenAddrs;
    mapping(address => address) public yearnVaults;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 100_000e6;
    uint256 public minFuzzAmount = 1_000_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Add to Yearn Role Manager;
        chad = yearnRoleManager.getDaddy();
        keeper = yearnRoleManager.getKeeper();

        // Set asset
        asset = ERC20(tokenAddrs["USDC"]);
        weth = tokenAddrs["WETH"];

        // Set decimals
        decimals = asset.decimals();

        preDepositFactory = new PreDepositFactory(
            management,
            acrossBridge,
            relayLinkBridge,
            address(yearnRoleManager)
        );

        vm.prank(management);
        preDepositFactory.setTargetRollupId(targetNetworkId);

        depositRelayer = preDepositFactory.DEPOSIT_RELAYER();
        shareReceiver = ShareReceiver(depositRelayer.SHARE_RECEIVER());

        stbVault = IVault(deployNewVault(address(asset)));

        yearnVault = IVault(yearnVaults[address(asset)]);

        vm.prank(management);
        preDepositVault = IVault(
            preDepositFactory.deployPreDeposit(
                address(asset),
                address(yearnVault),
                address(stbVault)
            )
        );

        strategy = IStrategyInterface(
            depositRelayer.stbDepositor(address(asset))
        );

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(chad);
        yearnRoleManager.addNewVault(address(preDepositVault), 69);

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(chad, "chad");
        vm.label(address(preDepositVault), "preDepositVault");
        vm.label(address(stbVault), "stbVault");
        vm.label(address(yearnVault), "yearnVault");
        vm.label(address(depositRelayer), "depositRelayer");
        vm.label(address(preDepositFactory), "preDepositFactory");
    }

    function newPreDepositVault(address _asset) public returns (address) {
        address _yearnVault = yearnVaults[_asset];
        address _stbVault = deployNewVault(_asset);
        vm.prank(management);
        return
            preDepositFactory.deployPreDeposit(_asset, _yearnVault, _stbVault);
    }

    function deployNewVault(address _asset) public returns (address) {
        vm.prank(chad);
        address _vault = yearnRoleManager.newVault(
            _asset,
            101,
            type(uint256).max
        );

        return _vault;
    }

    // For checking the amounts in the strategy
    function checkVaultTotals(
        IVault _vault,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _vault.totalAssets();
        uint256 _balance = ERC20(_vault.asset()).balanceOf(address(_vault));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        yearnVaults[
            tokenAddrs["USDC"]
        ] = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        yearnVaults[
            tokenAddrs["DAI"]
        ] = 0x028eC7330ff87667b6dfb0D94b954c820195336c;
        yearnVaults[
            tokenAddrs["WETH"]
        ] = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
    }
}
