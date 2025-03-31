// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {STBDepositor} from "./STBDepositor.sol";
import {ShareReceiver} from "./ShareReceiver.sol";
import {DepositRelayer} from "./DepositRelayer.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

// TODO:
// Deposit and Withdraw limit modules?
// Withdraw option
// ---- Keep in relayer, no withdraws (maybe a sweep)
// ---- send to share receiver, only allow specific transfers/withdraw
// ---- send wherever then whitelist who can withdraw from the module
contract PreDepositFactory is Governance2Step {
    event PreDepositDeployed(address indexed asset, address indexed vault);

    address public constant YEARN_ROLE_MANAGER =
        address(0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41);

    IVaultFactory public constant VAULT_FACTORY =
        IVaultFactory(0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F);

    DepositRelayer public immutable DEPOSIT_RELAYER;
    ShareReceiver public immutable SHARE_RECEIVER;
    uint32 public immutable TARGET_NETWORK_ID;

    mapping(address => address) public preDepositVault;
    mapping(address => address) public stbDepositor;

    constructor(
        address _governance,
        address _acrossBridge,
        uint32 _targetNetworkId
    ) Governance2Step(_governance) {
        SHARE_RECEIVER = new ShareReceiver(_governance);
        DEPOSIT_RELAYER = new DepositRelayer(
            _governance,
            _acrossBridge,
            address(SHARE_RECEIVER)
        );
        TARGET_NETWORK_ID = _targetNetworkId;
    }

    function deployPreDeposit(
        address _asset,
        address _yearnVault,
        address _stbVault
    ) external onlyGovernance returns (address _vault) {
        // Deploy new vault
        _vault = VAULT_FACTORY.deploy_new_vault(
            _asset,
            string(
                abi.encodePacked("Katana Pre-Deposit", ERC20(_asset).symbol())
            ),
            string(abi.encodePacked("kpd", ERC20(_asset).symbol())),
            address(this),
            1 days
        );

        // Deploy STBDepositor strategy
        IStrategyInterface _stbDepositor = IStrategyInterface(
            address(
                new STBDepositor(
                    _asset,
                    string(
                        abi.encodePacked(
                            "Katana ",
                            ERC20(_asset).symbol(),
                            "STB Depositor"
                        )
                    ),
                    _stbVault,
                    _vault,
                    TARGET_NETWORK_ID
                )
            )
        );

        _stbDepositor.setPendingManagement(governance);

        // Add strategies to vault
        IVault(_vault).set_role(address(this), Roles.ALL);

        IVault(_vault).add_strategy(address(_yearnVault));
        IVault(_vault).update_max_debt_for_strategy(
            address(_yearnVault),
            type(uint256).max
        );

        IVault(_vault).add_strategy(address(_stbDepositor));
        IVault(_vault).update_max_debt_for_strategy(
            address(_stbDepositor),
            type(uint256).max
        );

        IVault(_vault).set_deposit_limit(type(uint256).max);

        IVault(_vault).set_role(address(this), 0);
        IVault(_vault).transfer_role_manager(address(YEARN_ROLE_MANAGER));

        // Add vault to relayer
        DEPOSIT_RELAYER.setVault(_asset, _vault);

        preDepositVault[_asset] = _vault;
        stbDepositor[_asset] = address(_stbDepositor);

        emit PreDepositDeployed(_asset, _vault);

        return _vault;
    }
}
