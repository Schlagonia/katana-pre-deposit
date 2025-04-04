// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {Accountant} from "./Accountant.sol";
import {STBDepositor} from "./STBDepositor.sol";
import {ShareReceiver} from "./ShareReceiver.sol";
import {DepositRelayer} from "./DepositRelayer.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

/// @title Pre-Deposit Factory
/// @notice This contract is used to deploy new pre-deposit vaults
/// @dev Can only be called by the governance
contract PreDepositFactory is Governance2Step {
    /// @notice Event emitted when a new pre-deposit vault is deployed
    event PreDepositDeployed(address indexed asset, address indexed vault);

    /// @notice Address to give the Role Manager position to.
    address public constant YEARN_ROLE_MANAGER =
        address(0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41);

    /// @notice Global v3.0.4 vault factory
    IVaultFactory public constant VAULT_FACTORY =
        IVaultFactory(0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F);

    /// @notice The network id for Katana for the LxLy bridge/
    uint32 public immutable TARGET_NETWORK_ID;

    /// @notice The accountant that will be used to take 100% of yield
    Accountant public immutable ACCOUNTANT;

    /// @notice The share receiver that will be used to receive the vault shares
    ShareReceiver public immutable SHARE_RECEIVER;

    /// @notice The relayer that will be used to deposit funds into the vaults
    DepositRelayer public immutable DEPOSIT_RELAYER;

    /// @notice Token to stb depositor strategy for any deployed vaults
    mapping(address => address) public stbDepositor;

    /// @notice Token to vault mapping for any deployed vaults
    mapping(address => address) public preDepositVault;

    constructor(
        address _governance,
        address _acrossBridge,
        uint32 _targetNetworkId
    ) Governance2Step(_governance) {
        DEPOSIT_RELAYER = new DepositRelayer(_governance, _acrossBridge);
        ACCOUNTANT = Accountant(DEPOSIT_RELAYER.ACCOUNTANT());
        SHARE_RECEIVER = ShareReceiver(DEPOSIT_RELAYER.SHARE_RECEIVER());
        TARGET_NETWORK_ID = _targetNetworkId;
    }

    /// @notice Deploy and setups a new pre-deposit vault
    /// @dev Can only be called by the governance
    /// @param _asset The asset to deploy the vault for
    /// @param _yearnVault The yearn vault to use as first strategy
    /// @param _stbVault The stb vault that will be bridged to Katana
    /// @return _vault The address of the new vault
    function deployPreDeposit(
        address _asset,
        address _yearnVault,
        address _stbVault
    ) external onlyGovernance returns (address _vault) {
        require(
            preDepositVault[_asset] == address(0),
            "Vault already deployed"
        );

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

        IVault(_vault).set_accountant(address(ACCOUNTANT));
        IVault(_vault).set_deposit_limit(type(uint256).max);
        // IVault(_vault).set_deposit_limit_module(address(SHARE_RECEIVER), true);
        // IVault(_vault).set_withdraw_limit_module(address(SHARE_RECEIVER));

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
