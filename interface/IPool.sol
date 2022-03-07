// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

interface IPool {
  function changePoolMeta(string memory name, string memory site) external;

  function updatePoolOptions(
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) external;

  function pause(bool status) external;

  function calculateClaimReward(address account, uint256 stakeIndex) external returns (uint256);

  function stake(uint256 amount, address referer) external;

  function offchainClaim(address account, uint256 stakeIndex) external;

  function claim() external;

  event StakeCreated(uint256 stakeIndex, address referer);

  event Claim(uint256 stakeIndex);

  event PoolMetaChanged(string newName, string newSite);

  event PoolOptionsChanged(
    uint256 minStakeTokens,
    uint256[] refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  );
}

interface IPoolXPi {
  function changePoolMeta(string memory name, string memory site) external;

  function updatePoolOptions(
    uint256 minStakeTokens,
    address poolAccount
  ) external;

  function pause(bool status) external;

  function calculateClaimReward(address account, uint256 stakeIndex) external returns (uint256);

  function stake(uint256 amount, address referer) external;

  function offchainClaim(address account, uint256 stakeIndex) external;

  function claim() external;

  event StakeCreated(uint256 stakeIndex, address referer);
  
  event Claim(uint256 stakeIndex);

  event PoolMetaChanged(string newName, string newSite);

  event PoolOptionsChanged(
    uint256 minStakeTokens,
    uint256[] refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  );
}
