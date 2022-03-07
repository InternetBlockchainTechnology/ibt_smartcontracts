// SPDX-License-Identifier: MIT

import "./IPoolManager.sol";

pragma solidity ^0.8.8;

interface IERC20IBT {

  function poolManagerTransferFrom(address from, address to, uint256 amount) external;

  function poolManagerMint(address account, uint256 amount) external;

  function poolManagerBurn(address account, uint256 amount) external;

  function setPoolManager(IPoolManager poolManager) external;

  event Burn(address account, uint256 value, uint256 timestamp);
}
