// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./PoolXPi.sol";
import "./lib/Ownable.sol";
import "./interface/IPoolManager.sol";
import "./interface/IPoolXPiFactory.sol";

contract PoolXPiFactory is IPoolXPiFactory, Ownable {
  bool created;

  function create(
    address owner,
    IPoolManager poolManager,
    uint256 minStakeTokens,
    address poolAccount
  ) external onlyOwner returns (IPool) {
    require(created == false);
    created = true;
    PoolXPi pool = new PoolXPi(poolManager, minStakeTokens, poolAccount);
    pool.transferOwnership(owner);
    return IPool(address(pool));
  }
}
