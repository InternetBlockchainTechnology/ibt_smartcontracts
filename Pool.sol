// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./lib/SafeMath.sol";
import "./lib/Moment.sol";
import "./lib/Pausable.sol";
import "./AccessControl.sol";
import "./interface/IPoolManager.sol";
import "./interface/IPool.sol";
import "./interface/IOwnable.sol";

contract Pool is IPool, AccessControl, Pausable {
  using SafeMath for uint256;

  uint256 _timelapsOffset = 0;

  IPoolManager public _poolManager;

  uint256 public _minStakeTokens;
  uint256 public _burnPercent = 85;
  uint256 public _stakeLifetimeInYears = 1;

  struct Stake {
    uint256 body;
    uint256 createdAt;
    uint256 expiresIn;
    uint256 lastClaim;
    bool isDone;
  }

  Stake[] public _poolStakes;

  mapping(address => Stake[]) public _stakes;
  mapping(address => uint256) public _lastAccountExpiriedStakeIndex;


  address public _poolAccount;
  uint256 public _maxRefPercent = 1500;
  uint256 public _maxRefLevels = 1500;
  uint256 public _poolRefPercent;
  uint256[] public _refLevelsWithPercent;


  mapping(address => address) public _referralToReferer;
  mapping(address => address[]) public _refererToReferrals;
  mapping(address => uint256) private _referralIndex;

  string public _name;
  string public _site;

  uint256 _startedAt;

  constructor(
    IPoolManager poolManager,
    string memory name,
    string memory site,
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) {
    updatePoolOptions(
      name,
      site,
      minStakeTokens,
      refLevelsWithPercent,
      poolRefPercent,
      poolAccount
    );

    bytes4[] memory permissions = new bytes4[](1);

    permissions[0] = IPool.pause.selector;
    setSystemAdministrator(IOwnable(address(poolManager)).owner(), permissions);

    bytes4[] memory additionalAdminPermissions = new bytes4[](1);
    additionalAdminPermissions[0] = IPool.updatePoolOptions.selector;

    setAdditionalAdminPermissions(additionalAdminPermissions);
    
    _poolManager = poolManager;

    _startedAt = block.timestamp;
  }

  // function changePoolMeta(string memory name, string memory site) public checkAccess(IPool.changePoolMeta.selector) {
  //   _name = name;
  //   _site = site;
  //   emit PoolMetaChanged(name, site);
  // }

  function updatePoolOptions(
    string memory name,
    string memory site,
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) public checkAccess(IPool.updatePoolOptions.selector) {
    require(minStakeTokens > 0);
    require(poolAccount != address(0));
    require(refLevelsWithPercent.length <= _maxRefLevels);
    uint256 totalRefPercent = 0;
    for (uint8 i = 0; i < refLevelsWithPercent.length; i++) {
      totalRefPercent = totalRefPercent.add(refLevelsWithPercent[i]);
    }
    require(_maxRefPercent.sub(totalRefPercent).sub(poolRefPercent) == 0);
    _minStakeTokens = minStakeTokens;
    _refLevelsWithPercent = refLevelsWithPercent;
    _poolRefPercent = poolRefPercent;
    _poolAccount = poolAccount;
    _name = name;
    _site = site;
    emit PoolOptionsChanged(
      name,
      site,
      minStakeTokens,
      refLevelsWithPercent,
      poolRefPercent,
      poolAccount
    );
  }

  function pause(bool status) external {
    require(_msgSender() == address(_poolManager) || hasPermission(_msgSender(), IPool.pause.selector));
    status == true ? _pause() : _unpause();
  }

  /* STAKE SECTION */


  function calculateClaimReward(address account, uint256 stakeIndex) public view returns (uint256) {
    uint256 currentTimestamp = block.timestamp;
    uint256 totalReward = 0;

    Stake storage stakeItem = _stakes[account][stakeIndex];

    uint256[][] memory stakeProfitTable = _poolManager.getStakeProfitTable();

    for (uint256 i = 0; i < stakeProfitTable.length; i++) {
      if (stakeItem.expiresIn <= stakeProfitTable[i][0] || currentTimestamp <= stakeProfitTable[i][0]) break;
      if (stakeItem.createdAt >= stakeProfitTable[i][1]) continue;

      if (stakeItem.createdAt >= stakeProfitTable[i][0] || stakeItem.expiresIn <= stakeProfitTable[i][1]) {
        uint256 timeFrom = stakeItem.lastClaim < stakeProfitTable[i][0] ? stakeProfitTable[i][0] : stakeItem.lastClaim;
        uint256 timeTo = currentTimestamp;
        if (currentTimestamp >= stakeItem.expiresIn) {
          timeTo = stakeItem.expiresIn;
        } else if (currentTimestamp > stakeProfitTable[i][1]) {
          timeTo = stakeProfitTable[i][1];
        }

        totalReward = totalReward.add(calculateClaimRewardByPeriod(stakeItem.body, stakeProfitTable[i][2], timeFrom, timeTo));
      }
    }

    return totalReward;
  }

  function calculateClaimRewardByPeriod(
    uint256 body,
    uint256 profitPercent,
    uint256 timeFrom,
    uint256 timeTo
  ) internal pure returns (uint256) {
    uint256 daysPassed = Moment.diffDays(timeFrom, timeTo);
    uint256 secondsPassed = Moment.diffSeconds(timeFrom, timeTo);
    uint256 perPeriodProfit = body.mul(profitPercent).div(100);
    uint256 full30DaysPassed = daysPassed.div(30);
    uint256 reward = 0;
    if (full30DaysPassed >= 1) {
      reward = reward.add(full30DaysPassed.mul(perPeriodProfit));
    }

    uint256 remainDays = daysPassed.sub(full30DaysPassed.mul(30));
    uint256 remainSeconds = secondsPassed.sub(daysPassed.mul(1 days));
    uint256 remainPercentOfPeriod = remainDays.mul(1 days).add(remainSeconds).mul(100).mul(10000).div(30 days);
    uint256 remainProfit = (perPeriodProfit.mul(remainPercentOfPeriod)).div(100).div(10000);
    return reward.add(remainProfit);
  }

  function stake(uint256 amount, address referer) external whenNotPaused {
    if (referer == address(0)) {
      require(block.timestamp > _startedAt + 24 hours * 3);
    }
    require(_msgSender() == owner() || (_msgSender() != owner() && _stakes[owner()].length > 0));
    require(amount >= _minStakeTokens);
    if (_stakes[referer].length == 0 || referer == address(0)) {
      referer = owner();
    }

    uint256 createdAt = block.timestamp;
    uint256 expiresIn = Moment.addYears(createdAt, _stakeLifetimeInYears);

    Stake memory accountStake = Stake({
      body: amount,
      createdAt: createdAt,
      expiresIn: expiresIn,
      lastClaim: createdAt,
      isDone: false
    });

    _stakes[_msgSender()].push(accountStake);

    _poolStakes.push(accountStake);

    uint256 burnAmount = amount.mul(_burnPercent).div(100);

    _poolManager.burn(_msgSender(), burnAmount);

    if (_msgSender() != referer &&  _referralToReferer[_msgSender()] == address(0)) {
      registration(_msgSender(), referer);
    }

    distributeRewards(_msgSender(), amount);

    _poolManager.appendStake(amount, createdAt, expiresIn);

    emit StakeCreated(_stakes[_msgSender()].length - 1, _referralToReferer[_msgSender()]);
  }

  function claimFromStake(uint256 stakeIndex) external {
    address account = _msgSender();
    require(_stakes[account].length > 0, "You must have stakes to collect rewards");
    require(_stakes[account][stakeIndex].body > 0 && !_stakes[account][stakeIndex].isDone, "already done");
    uint256 reward = calculateClaimReward(account, stakeIndex);
    _stakes[account][stakeIndex].lastClaim = block.timestamp;
    if (block.timestamp >= _stakes[account][stakeIndex].expiresIn) {
      _lastAccountExpiriedStakeIndex[account] = stakeIndex;
      _stakes[account][stakeIndex].isDone = true;
    }
    _poolManager.mint(account, reward);
    emit Claim(stakeIndex);
  }

  function offchainClaim(address account, uint256 stakeIndex) external {
    require(_stakes[account].length > 0);
    require(_stakes[account][stakeIndex].body > 0 && block.timestamp >= _stakes[account][stakeIndex].expiresIn && !_stakes[account][stakeIndex].isDone);
    uint256 reward = calculateClaimReward(account, stakeIndex);
    _stakes[account][stakeIndex].lastClaim = block.timestamp;
    _stakes[account][stakeIndex].isDone = true;
    _lastAccountExpiriedStakeIndex[account] = stakeIndex;
    _poolManager.mint(account, reward);
    emit Claim(stakeIndex);
  }

  function claim() external {
    require(_stakes[_msgSender()].length > 0, "You must have stakes to collect rewards");
    uint256 totalClaimReward = 0;
    address account = _msgSender();
    for (uint256 i = _lastAccountExpiriedStakeIndex[account]; i < _stakes[account].length; i++) {
      if(_stakes[account][i].isDone) continue;
      uint256 reward = calculateClaimReward(account, i);
      _stakes[account][i].lastClaim = block.timestamp;
      if (_stakes[account][i].lastClaim >= _stakes[account][i].expiresIn) {
        _lastAccountExpiriedStakeIndex[account] = i;
        _stakes[account][i].isDone = true;
      }
      totalClaimReward = totalClaimReward.add(reward);
      emit Claim(i);
    }

    _poolManager.mint(account, totalClaimReward);
  }

  /* \STAKE SECTION */

  /* REF SECTION */

  function registration(address referral, address referer) internal  {
    require(_referralToReferer[referral] == address(0), "Already tied");
    _referralToReferer[referral] = referer;
    _refererToReferrals[referer].push(referral);
    _referralIndex[referral] = _refererToReferrals[referer].length - 1;
  }

  function distributeRewards(address referral, uint256 stakeBody) internal {
    if (_referralToReferer[referral] == address(0)) {
      uint256 rewardAmount = stakeBody.mul(_maxRefPercent).div(10000);
      _poolManager.transferFrom(referral, _poolAccount, rewardAmount);
      return;
    }

    uint256 distributedPercents = 0;
    address referer = _referralToReferer[referral];

    for (uint8 i = 0; i < _refLevelsWithPercent.length; i++) {
      uint256 refLevelRewardAmount = stakeBody.mul(_refLevelsWithPercent[i]).div(10000);
      _poolManager.transferFrom(referral, referer, refLevelRewardAmount);
      distributedPercents = distributedPercents.add(_refLevelsWithPercent[i]);
      if (_referralToReferer[referer] == address(0)) break;
      referer = _referralToReferer[referer];
    }

    uint256 remainPercent = _maxRefPercent.sub(distributedPercents);
    uint256 poolRewardAmount = stakeBody.mul(remainPercent).div(10000);

    if (poolRewardAmount > 0) {
      _poolManager.transferFrom(referral, _poolAccount, poolRewardAmount);
    }
  }

  /* \REF SECTION */
}
