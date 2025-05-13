// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Base4626Compounder, ERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPolygonZkEVMBridge} from "./interfaces/IPolygonZkEVMBridge.sol";

import {PreDepositFactory} from "./PreDepositFactory.sol";

contract STBDepositor is Base4626Compounder {
    using SafeERC20 for ERC20;

    event KatanaReceiverSet(address indexed newKatanaReceiver);

    IPolygonZkEVMBridge public constant ZKEVM_BRIDGE =
        IPolygonZkEVMBridge(0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe);

    address public immutable PRE_DEPOSIT_VAULT;

    PreDepositFactory public immutable PRE_DEPOSIT_FACTORY;

    address public katanaReceiver;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _preDepositVault
    ) Base4626Compounder(_asset, _name, _vault) {
        PRE_DEPOSIT_VAULT = _preDepositVault;
        PRE_DEPOSIT_FACTORY = PreDepositFactory(msg.sender);
    }

    function bridgeFunds(uint256 _amount) external onlyManagement {
        require(katanaReceiver != address(0), "KATANA RECEIVER NOT SET");
        uint256 assetBalance = balanceOfAsset();
        if (assetBalance > 0) {
            _deployFunds(assetBalance);
        }

        // Use min of amount or shares
        uint256 shares = balanceOfVault();
        if (_amount < shares) {
            shares = _amount;
        }

        require(shares > 0, "!shares");

        ERC20(address(vault)).forceApprove(address(ZKEVM_BRIDGE), shares);

        uint32 targetRollupId = PRE_DEPOSIT_FACTORY.targetRollupId();
        require(targetRollupId != 0, "!targetRollupId");

        ZKEVM_BRIDGE.bridgeAsset(
            targetRollupId,
            katanaReceiver,
            shares,
            address(vault),
            true,
            ""
        );
    }

    function setKatanaReceiver(
        address _katanaReceiver
    ) external onlyManagement {
        require(_katanaReceiver != address(0), "ZERO ADDRESS");

        katanaReceiver = _katanaReceiver;
        emit KatanaReceiverSet(_katanaReceiver);
    }

    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (_receiver == PRE_DEPOSIT_VAULT) {
            return super.availableDepositLimit(_receiver);
        }
        return 0;
    }
}
