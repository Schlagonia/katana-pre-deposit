// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {Base4626Compounder, ERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPolygonZkEVMBridge} from "./interfaces/IPolygonZkEVMBridge.sol";

// Do we want a timelock period to bridge the funds?
// Do we want a second signer to okay the bridging
contract STBDepositor is Base4626Compounder {
    using SafeERC20 for ERC20;

    IPolygonZkEVMBridge public constant ZKEVM_BRIDGE =
        IPolygonZkEVMBridge(0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe);

    address public immutable PRE_DEPOSIT_VAULT;

    uint32 public immutable TARGET_NETWORK_ID;

    address public katanaReceiver;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _preDepositVault,
        uint32 _targetNetworkId
    ) Base4626Compounder(_asset, _name, _vault) {
        PRE_DEPOSIT_VAULT = _preDepositVault;
        TARGET_NETWORK_ID = _targetNetworkId;
    }

    function bridgeFunds() external onlyManagement {
        require(katanaReceiver != address(0), "KATANA RECEIVER NOT SET");
        uint256 assetBalance = balanceOfAsset();
        if (assetBalance > 0) {
            _deployFunds(assetBalance);
        }
        uint256 shares = balanceOfVault();

        ERC20(address(vault)).forceApprove(address(ZKEVM_BRIDGE), shares);

        ZKEVM_BRIDGE.bridgeAsset(
            TARGET_NETWORK_ID,
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
