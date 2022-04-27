// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./lib/Ownable.sol";
import "./interface/IAccessControl.sol";

contract AccessControl is IAccessControl, Ownable {
  struct Role {
    mapping(bytes4 => bool) permissions;
    uint8[] appPermissions;
    bytes32 role;
  }

 uint8[] private _allAppPermissions = new uint8[](1);

  mapping(bytes32 => Role) public _role;
  mapping(address => bytes32) public _accountRole;
  mapping(bytes32 => address[]) public _roleAccounts;

  bytes4[] public _adminPermissions;
  mapping(bytes4 => bool) public _allowedSelectors;
  
  bytes32 private _adminRole;
  address private _preventChangesForAddress;

  bool private _additionalPermissionsInstalled;
  string private _systemAdministratorRole = "systemAdministrator";

  modifier checkAccess(bytes4 selector) {
    require(
      hasPermission(_msgSender(), selector) || _msgSender() == owner(),
      "AccessControl: You don't have permission to call this function"
    );
    _;
  }

  constructor() {
    _adminPermissions.push(IAccessControl.createRole.selector);
    _allowedSelectors[IAccessControl.createRole.selector] = true;
    _adminPermissions.push(IAccessControl.grantRole.selector);
    _allowedSelectors[IAccessControl.grantRole.selector] = true;
    _adminPermissions.push(IAccessControl.grantRoleBatch.selector);
    _allowedSelectors[IAccessControl.grantRoleBatch.selector] = true;
    _adminPermissions.push(IAccessControl.revokeRole.selector);
    _allowedSelectors[IAccessControl.revokeRole.selector] = true;
    _adminPermissions.push(IAccessControl.revokeRoleBatch.selector);
    _allowedSelectors[IAccessControl.revokeRoleBatch.selector] = true;
    _allAppPermissions.push(100);

    _adminRole = bytes32(bytes("admin"));
    _createRole(_adminRole, _adminPermissions, _allAppPermissions);
  }

  function setAdditionalAdminPermissions(bytes4[] memory selectors) internal {
    require(_additionalPermissionsInstalled == false);
    for (uint8 i = 0; i < selectors.length; i++) {
      _adminPermissions.push(selectors[i]);
      _allowedSelectors[selectors[i]] = true;
      _role[bytes32(bytes("admin"))].permissions[selectors[i]] = true;
    }
    _additionalPermissionsInstalled = true;
    emit ContractPermissions(_adminPermissions);

  }

  function allowSelectors(bytes4[] memory permissions, bool status) internal {
    for (uint8 i = 0; i < permissions.length; i++) {
      _allowedSelectors[permissions[i]] = status;
    }
  }

  function setSystemAdministrator(address account, bytes4[] memory permissions) internal {
    require(_preventChangesForAddress == address(0));
    allowSelectors(permissions, true);
    _createRole(bytes32(bytes(_systemAdministratorRole)), permissions, new uint8[](0));
    _grantRole(account, bytes32(bytes(_systemAdministratorRole)));
    allowSelectors(permissions, false);
    _preventChangesForAddress = account;
    //emit RoleCreated(_systemAdministratorRole, permissions, new uint8[](0));
  }

  function hasPermission(address account, bytes4 selector) public view returns(bool) {
    return _role[_accountRole[account]].permissions[selector];
  }

  function getAccountRole(address account) public view returns(string memory) {
    return string(abi.encodePacked(_accountRole[account]));
  }

  function createRole(string calldata name, bytes4[] memory selectors, uint8[] memory appPermissions)
    external
    checkAccess(IAccessControl.createRole.selector)
  { 
    bytes32 roleBytes = bytes32(bytes(name));
    require(roleBytes != _role[bytes32(bytes(_systemAdministratorRole))].role);
    require(roleBytes != _adminRole); //"AccessControl: you can't change admin permissions"
    _createRole(roleBytes, selectors, appPermissions);
    emit RoleCreated(name, selectors, appPermissions);
  }

  function _createRole(bytes32 name, bytes4[] memory selectors, uint8[] memory appPermissions) internal {
    if (_role[name].role != bytes32(0)) {
      for (uint8 i = 0; i < _adminPermissions.length; i++) {
        _role[name].permissions[_adminPermissions[i]] = false;
      }
    }

    _role[name].role = name;

    for (uint8 i = 0; i < selectors.length; i++) {
      require(_allowedSelectors[selectors[i]]); //"AccessControl: one of the selectors is not allowed"
      require(selectors[i] != IAccessControl.createRole.selector || _msgSender() == owner());
      _role[name].permissions[selectors[i]] = true;
    }

    _role[name].appPermissions = appPermissions;
  }

  function grantRole(address account, string memory role) public checkAccess(IAccessControl.grantRole.selector) {
    require(account != address(0)); // "AccessControl: prevent grant zero address"
    require(account != _msgSender()); // "AccessControl: you can't grant self another role"
    require(account != _preventChangesForAddress); // "AccessControl: excluded account"
    require(account != owner()); // "AccessControl: you can't change owner account"

    _grantRole(account, bytes32(bytes(role)));
    emit RoleGranted(account, role);
  }

  function _grantRole(address account, bytes32 role) internal {
    if (_accountRole[account] != bytes32(0)) {
      uint256 accountsCount = _roleAccounts[_accountRole[account]].length;

      if (accountsCount == 1) {
        _roleAccounts[_accountRole[account]].pop();
      } else {
        for (uint256 i = 0; i < accountsCount; i++) {
          if (account == _roleAccounts[_accountRole[account]][i]) {
            _roleAccounts[_accountRole[account]][i] = _roleAccounts[_accountRole[account]][accountsCount - 1];
            _roleAccounts[_accountRole[account]].pop();
            break;
          }
        }
      }
    }
    _accountRole[account] = role;
    _roleAccounts[role].push(account);
  }

  function grantRoleBatch(address[] calldata accounts, string[] calldata roles) external checkAccess(IAccessControl.grantRoleBatch.selector) {
    require(accounts.length == roles.length); //"AccessControl: accounts size not equal to roles size"
    for (uint256 i = 0; i < accounts.length; i++) {
      grantRole(accounts[i], roles[i]);
    }
  }

  function revokeRole(address account) external checkAccess(IAccessControl.revokeRole.selector) {
    require(account != _msgSender()); //"AccessControl: you can't revoke your own role"
    require(_accountRole[account] != bytes32(0)); //"AccessControl: account already at base role"
    grantRole(account, "");
  }

  function revokeRoleBatch(address[] calldata accounts) external checkAccess(IAccessControl.revokeRoleBatch.selector) {
    for (uint256 i = 0; i < accounts.length; i++) {
      grantRole(accounts[i], "");
    }
  }
}
