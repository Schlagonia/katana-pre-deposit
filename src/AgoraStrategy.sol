// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";

contract AgoraStrategy is BaseHealthCheck {
    using SafeERC20 for ERC20;

    address public immutable FUND_MANAGER;
    address public immutable PRE_DEPOSIT_VAULT;

    constructor(
        address _asset,
        address _fundManager,
        address _preDepositVault
    ) BaseHealthCheck(_asset, "Agora Strategy") {
        asset.forceApprove(address(_fundManager), type(uint256).max);
        FUND_MANAGER = _fundManager;
        PRE_DEPOSIT_VAULT = _preDepositVault;
    }

    function _deployFunds(uint256 _amount) internal override {}

    function _freeFunds(uint256 _amount) internal override {}

    function _harvestAndReport() internal override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (_receiver != PRE_DEPOSIT_VAULT) {
            return 0;
        }

        return type(uint256).max;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        asset.forceApprove(FUND_MANAGER, 0);
    }
}
