// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface IYearnRoleManager {
    function newVault(
        address _asset,
        uint256 _category,
        uint256 _depositLimit
    ) external returns (address);
    function addNewVault(address _vault, uint256 _category) external;
    function getDaddy() external view returns (address);
    function getKeeper() external view returns (address);
}
