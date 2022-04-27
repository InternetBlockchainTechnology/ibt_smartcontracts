// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

interface IAccessControl {
  event RoleCreated(string name, bytes4[] permissions, uint8[] appPermissions);
  event RoleGranted(address indexed account, string role);
  event RoleRemoved(string name);
  event ContractPermissions(bytes4[] permissions);

  function hasPermission(address account, bytes4 selector) external view returns(bool);

  function getAccountRole(address account) external view returns(string memory);
  
  function createRole(string calldata name, bytes4[] memory selectors, uint8[] memory appPermissions) external;

  function grantRole(address account, string memory role) external;

  function grantRoleBatch(address[] calldata accounts, string[] calldata roles) external;

  function revokeRole(address account) external;

  function revokeRoleBatch(address[] calldata accounts) external;
}