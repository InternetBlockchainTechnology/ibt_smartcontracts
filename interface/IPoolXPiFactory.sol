// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./IPoolManager.sol";
import "./IPool.sol";

interface IPoolXPiFactory {
  function create(
    address owner,
    IPoolManager poolManager,
    uint256 minStakeTokens,
    address poolAccount
  ) external returns (IPool);
}
