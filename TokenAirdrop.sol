// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./ERC20/ERC20.sol";
import "./lib/Ownable.sol";
import "./interface/IPoolManager.sol";
import "./interface/IERC20IBT.sol";

contract TokenAirdrop is ERC20, IERC20IBT, Ownable {

  IPoolManager public _poolManager;

  mapping(address => bool) public _whiteList;

  string private _name = "IBT Air";
  string private _symbol = "IBT Air";

  constructor() ERC20(_name, _symbol) {
    _mint(_msgSender(), 180000 * 10 ** decimals());
    _whiteList[_msgSender()] = true;
  }

  modifier onlyPoolManager() {
    require(_msgSender() == address(_poolManager), "Only poolManager can call this function");
    _;
  }

  function burn(uint256 amount) external returns(bool) {
    _burn(_msgSender(), amount);
    emit Burn(_msgSender(), amount, block.timestamp);
    return true;
  }

  function poolManagerTransferFrom(address from, address to, uint256 amount) external onlyPoolManager {
    _transfer(from, to, amount);
  }

  function poolManagerBurn(address account, uint256 amount) external onlyPoolManager {
    _burn(account, amount);
  }

  function poolManagerMint(address account, uint256 amount) external onlyPoolManager {
    _mint(account, amount);
  }

  function setPoolManager(IPoolManager poolManager) external onlyOwner {
    require(address(_poolManager) == address(0), "Pool manager already installed");
    _poolManager = poolManager;
  }

  function addToWhiteList(address addr) external onlyOwner {
    _whiteList[addr] = true;
  }

  function removeFromWhiteList(address addr) external onlyOwner {
    _whiteList[addr] = false;
  }

  function transfer(address to, uint256 amount) public override returns(bool) {
    require(_whiteList[to] || _whiteList[_msgSender()]);
    address owner = _msgSender();
    _transfer(owner, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public override returns(bool) {
   require(_whiteList[from] || _whiteList[to] || _whiteList[_msgSender()]);
    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);
    return true;
  }
}