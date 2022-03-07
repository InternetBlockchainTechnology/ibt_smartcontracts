// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./IPoolManager.sol";
import "./IPool.sol";

interface IPoolFactory {
  function create(
    address owner,
    IPoolManager poolManager,
    string memory name,
    string memory site,
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) external returns (IPool);
}
