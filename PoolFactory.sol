// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./lib/Ownable.sol";
import "./Pool.sol";
import "./interface/IPoolManager.sol";
import "./interface/IPool.sol";
import "./interface/IPoolFactory.sol";

contract PoolFactory is IPoolFactory, Ownable {
  function create(
    address owner,
    IPoolManager poolManager,
    string memory name,
    string memory site, 
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) external onlyOwner returns(IPool) {
    Pool pool = new Pool(poolManager, name, site, minStakeTokens, refLevelsWithPercent, poolRefPercent, poolAccount);
    pool.transferOwnership(owner);
    return IPool(address(pool));
  }
}