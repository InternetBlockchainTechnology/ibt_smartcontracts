// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./ERC20/ERC20.sol";
import "./lib/Ownable.sol";
import "./interface/IPoolManager.sol";
import "./interface/IERC20IBT.sol";

contract TokenAirdrop is ERC20, IERC20IBT, Ownable {

  IPoolManager public _poolManager;
  address public _xpiAddress;

  string private _name = "International Blockchain Technology Airdrop";
  string private _symbol = "IBTA";

  constructor() ERC20(_name, _symbol) {
    _mint(_msgSender(), 180000 * 10 ** decimals());
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

  function setXPi(address xpiAddress) external onlyOwner {
    require(_xpiAddress == address(0), "Xpi address already installed");
    _xpiAddress = xpiAddress;
  }

  function transfer(address to, uint256 amount) public override returns(bool) {
    require(to == _xpiAddress || to == address(0), "Airdrop tokens only for staking");
    address owner = _msgSender();
    _transfer(owner, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public override returns(bool) {
    require(to == _xpiAddress || to == address(0), "Airdrop tokens only for staking");
    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);
    return true;
  }
}