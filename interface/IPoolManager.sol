// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

interface IPoolManager {
  
  function getStakeProfitTable() external view returns (uint256[][] memory);

  function getCurrentStakeProfitPercent() external view returns (uint256);

  function transferFrom(address from, address to, uint256 amount) external; 
  
  function transferFromAirdrop(address from, address to, uint256 amount) external; 

  function mint(address account, uint256 amount) external;

  function burn(address account, uint256 amount) external;

  function burnAirdrop(address account, uint256 amount) external;

  function appendStake(
    uint256 body,
    uint256 createdAt,
    uint256 expiriedAt
  ) external;

  function pause(bool status) external;

  function mintTeamReward() external returns(uint256);


  event PoolCreated(
    uint256 poolIndex,
    uint256 price
  );

  event TeamWalletChanged(uint256 index, address newWallet);
}
