// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";

/// Receives tokens from STB vaults. Deposits into the Katana Yearn vault and
/// disperses them to the recipients.
contract KatanaReceiver is Governance2Step {
    using SafeERC20 for ERC20;
    using SafeERC20 for IVault;

    event VaultSet(address indexed asset, address indexed vault);

    mapping(address => address) public vaults;

    constructor(address _owner) Governance2Step(_owner) {}

    function deposit(address _asset) public {
        address vault = vaults[_asset];
        require(vault != address(0), "Vault not found");

        uint256 balance = ERC20(_asset).balanceOf(address(this));
        require(balance > 0, "No balance");

        _deposit(_asset, vault, balance);
    }

    function _deposit(
        address _asset,
        address _vault,
        uint256 _balance
    ) internal {
        ERC20(_asset).forceApprove(_vault, _balance);
        IVault(_vault).deposit(_balance, address(this));
    }

    function setVault(address _asset, address _vault) external onlyGovernance {
        vaults[_asset] = _vault;
        emit VaultSet(_asset, _vault);
    }

    function disperse(
        address _asset,
        address[] calldata _recipients,
        uint256[] calldata _values
    ) external onlyGovernance {
        IVault vault = IVault(vaults[_asset]);
        require(address(vault) != address(0), "Vault not found");

        uint256 balance = ERC20(_asset).balanceOf(address(this));
        if (balance > 0) {
            _deposit(_asset, address(vault), balance);
        }

        require(_recipients.length == _values.length, "Invalid length");

        for (uint256 i = 0; i < _recipients.length; i++) {
            vault.safeTransfer(_recipients[i], _values[i]);
        }
    }
}
