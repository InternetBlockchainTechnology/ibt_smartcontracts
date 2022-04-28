// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./lib/SafeMath.sol";
import "./lib/Moment.sol";
import "./lib/Pausable.sol";
import "./AccessControl.sol";
import "./interface/IPoolManager.sol";
import "./interface/IPool.sol";
import "./interface/IOwnable.sol";

contract PoolXPi is IPoolXPi, AccessControl, Pausable {
  using SafeMath for uint256;

  IPoolManager public _poolManager;

  uint256 public _minStakeTokens;
  uint256 public _burnPercent = 85;
  uint256 public _stakeLifetimeInYears = 1;
  uint256 public _claimComission = 10;

  struct Stake {
    uint256 body;
    uint256 createdAt;
    uint256 expiresIn;
    uint256 lastClaim;
    bool isDone;
  }

  Stake[] public _poolStakes;
  uint256 private _lastExpiriedStakeIndex;

  mapping(address => Stake[]) public _stakes;
  mapping(address => uint256) private _lastAccountExpiriedStakeIndex;

  address public _poolAccount;

  struct RefererLevel {
    uint256 minStakesAmount;
    uint256 minReferrals;
    uint256 minReferralsStakesAmount;
    uint8 depth;
  }

  uint256 public _maxRefPercent = 15;
  uint256 public _maxDepth = 15;
  uint256 public _directRefPercent = 9;
  uint256 public _poolRefPercent = 1;

  RefererLevel[] public _refererLevels;

  mapping(address => address) public _referralToReferer;
  mapping(address => address[]) public _refererToReferrals;
  mapping(address => uint256) private _referralIndex;
  
  struct RefererStats {
    uint256 referralsCount;
    uint256 totalActiveStakesSum;
  }
  
  mapping(address => mapping(uint256 => RefererStats)) public _refererStats;
  mapping(address => mapping(address => uint256)) public _onLineReferral;

  string public _name;
  string public _site;

  uint256 _startedAt;

  constructor(
    IPoolManager poolManager,
    uint256 minStakeTokens,
    address poolAccount
  ) {
    updatePoolOptions("X3.14", "https://x314.site", minStakeTokens, poolAccount);

    bytes4[] memory permissions = new bytes4[](1);
    
    permissions[0] = IPoolXPi.pause.selector;
    // permissions[1] = IPool.changePoolMeta.selector;
    setSystemAdministrator(IOwnable(address(poolManager)).owner(), permissions);

    bytes4[] memory additionalAdminPermissions = new bytes4[](1);
    additionalAdminPermissions[0] = IPoolXPi.updatePoolOptions.selector;

    setAdditionalAdminPermissions(permissions);
    
    _poolManager = poolManager;

    _startedAt = block.timestamp;
  }

  function updateRefLevel(uint256 minStakesAmount, uint256 minReferrals, uint256 minReferralsStakesAmount, uint8 depth, uint256 index) external onlyOwner {
    _refererLevels[index] = RefererLevel({
      minStakesAmount: minStakesAmount,
      minReferrals: minReferrals,
      minReferralsStakesAmount: minReferralsStakesAmount,
      depth: depth
    });
  }

  function pushRefLevel(uint256 minStakesAmount, uint256 minReferrals, uint256 minReferralsStakesAmount, uint8 depth) external onlyOwner {
    _refererLevels.push(RefererLevel({
      minStakesAmount: minStakesAmount,
      minReferrals: minReferrals,
      minReferralsStakesAmount: minReferralsStakesAmount,
      depth: depth
    }));
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
    address poolAccount
  ) public override checkAccess(IPoolXPi.updatePoolOptions.selector) {
    require(minStakeTokens > 0);
    require(poolAccount != address(0));
    _minStakeTokens = minStakeTokens;
    _poolAccount = poolAccount;
    _name = name;
    _site = site;
    emit PoolOptionsChanged(
      name,
      site,
      minStakeTokens,
      new uint256[](0),
      0,
      poolAccount
    );
  }


  function pause(bool status) external {
    require(_msgSender() == address(_poolManager) || hasPermission(_msgSender(), IPoolXPi.pause.selector));
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
      if (stakeItem.lastClaim > stakeProfitTable[i][1]) continue;

      if (stakeItem.createdAt >= stakeProfitTable[i][0] || stakeItem.expiresIn <= stakeProfitTable[i][1]) {
        uint256 timeFrom = stakeItem.lastClaim < stakeProfitTable[i][0] ? stakeProfitTable[i][0] : stakeItem.lastClaim;

        bool currentTimestampOverOrExpires = currentTimestamp >= stakeItem.expiresIn;
        bool expiresIsOverPeriod = stakeItem.expiresIn > stakeProfitTable[i][1];
        bool currentTimestampOverPeriod = currentTimestamp > stakeProfitTable[i][1];

        uint256 timeTo = stakeItem.expiresIn;

        if (expiresIsOverPeriod && currentTimestampOverPeriod) {
          timeTo = stakeProfitTable[i][1];
        } else if (!currentTimestampOverOrExpires && !currentTimestampOverPeriod) {
          timeTo = currentTimestamp;
        }

        totalReward = totalReward.add(calculateClaimRewardByPeriod(stakeItem.body, stakeProfitTable[i][2], timeFrom, timeTo));
      }
    }

    if (currentTimestamp < stakeItem.expiresIn) {
      uint256 comission = totalReward.mul(_claimComission).div(100);
      totalReward = totalReward.sub(comission);
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

  function createStake(uint256 amount) internal returns(uint256) {
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

    uint256 stakeIndex = _stakes[_msgSender()].length - 1;

    _poolStakes.push(accountStake);

    _poolManager.appendStake(amount, createdAt, expiresIn);

    return stakeIndex;
  }

  function refFlow(uint256 stakeIndex, uint256 amount, address referer, bool isAirdrop) internal {
    if (stakeIndex == 0) {
      _refererStats[_msgSender()][0] = RefererStats({
        referralsCount: 0,
        totalActiveStakesSum: amount
      });

      for (uint256 i = 1; i <= _maxDepth; i++) {
        _refererStats[_msgSender()][i] = RefererStats({
          referralsCount: 0,
          totalActiveStakesSum: 0
        });
      }
    } else {
      _refererStats[_msgSender()][0].totalActiveStakesSum = _refererStats[_msgSender()][0].totalActiveStakesSum.add(amount);
    }

    if (_msgSender() != referer && _referralToReferer[_msgSender()] == address(0)) {
      registration(_msgSender(), referer);
      _refererStats[referer][1].totalActiveStakesSum = _refererStats[referer][1].totalActiveStakesSum.add(amount);
    }
    distributeRewards(_msgSender(), amount, isAirdrop);
  }

  function stakeAirdrop(uint256 amount, address referer) external whenNotPaused {
    if (referer == address(0)) {
      require(block.timestamp > _startedAt + 24 hours * 3);
    }
    require(_msgSender() == owner() || (_msgSender() != owner() && _stakes[owner()].length > 0));
    require(amount >= _minStakeTokens);
    if (_stakes[referer].length == 0 || referer == address(0)) {
      referer = owner();
    }

    uint256 stakeIndex = createStake(amount);

    _poolManager.burnAirdrop(_msgSender(), amount);

    refFlow(stakeIndex, amount, referer, true);

    emit StakeCreated(stakeIndex, referer);
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
    
    uint256 stakeIndex = createStake(amount);

    uint256 burnAmount = amount.mul(_burnPercent).div(100);

    _poolManager.burn(_msgSender(), burnAmount);

    refFlow(stakeIndex, amount, referer, false);

    emit StakeCreated(stakeIndex, referer);
  }

  function claimFromStake(uint256 stakeIndex) external {
    address account = _msgSender();
    require(_stakes[account].length > 0);
    require(_stakes[account][stakeIndex].body > 0 && !_stakes[account][stakeIndex].isDone);
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
    require(_stakes[account][stakeIndex].body > 0 && block.timestamp >= _stakes[account][stakeIndex].expiresIn && !_stakes[account][stakeIndex].isDone, "not expiried now");
    uint256 reward = calculateClaimReward(account, stakeIndex);
    _stakes[account][stakeIndex].lastClaim = block.timestamp;
    _stakes[account][stakeIndex].isDone = true;
    _lastAccountExpiriedStakeIndex[account] = stakeIndex;
    _poolManager.mint(account, reward);
    emit Claim(stakeIndex);
  }

  function claim() external {
    require(_stakes[_msgSender()].length > 0);
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
    require(_referralToReferer[referral] == address(0));
    _referralToReferer[referral] = referer;
    _refererToReferrals[referer].push(referral);
    _referralIndex[referral] = _refererToReferrals[referer].length - 1;
    _refererStats[referer][1].referralsCount++;
  }

  function transferFrom(address from, address to, uint256 amount, bool isAirdrop) internal {
    if (isAirdrop) {
      _poolManager.mint(to, amount);
    } else {
      _poolManager.transferFrom(from, to, amount);
    }
  }

  function distributeRewards(address referral, uint256 stakeBody, bool isAirdrop) internal {
    if (_referralToReferer[referral] == address(0)) {
      uint256 rewardAmount = stakeBody.mul(_maxRefPercent).div(100);
      transferFrom(referral, _poolAccount, rewardAmount, isAirdrop);
      return;
    }

    uint256 poolReward = stakeBody.mul(_poolRefPercent).div(100);

    address referer = _referralToReferer[referral];

    uint256 lvl1RefererReward = stakeBody.mul(_directRefPercent).div(100);

    transferFrom(referral, referer, lvl1RefererReward, isAirdrop);

    uint256 forDistribution = stakeBody.mul(_maxRefPercent).div(100).sub(lvl1RefererReward).sub(poolReward);
    uint256 upperLvlReferersReward = forDistribution;
    referer = _referralToReferer[referer];

    uint256 distributed = 0;

    for (uint256 i = 2; i <= _maxDepth; i++) {
      if (referer == address(0)) break;
      if (_onLineReferral[referer][referral] == 0) {
        _onLineReferral[referer][referral] = i;
        _refererStats[referer][0].referralsCount++;
        _refererStats[referer][i].referralsCount++; 
      }
      _refererStats[referer][i].totalActiveStakesSum = _refererStats[referer][i].totalActiveStakesSum.add(stakeBody);
      uint256 refererLevelIndex = getRefererLevelIndex(referer);
      uint256 reward = upperLvlReferersReward.div(3);

      upperLvlReferersReward = upperLvlReferersReward.sub(reward);
      if (refererLevelIndex == 100 || (refererLevelIndex != 100 && i > _refererLevels[refererLevelIndex].depth)) {
        referer = _referralToReferer[referer];
        continue;
      }
      transferFrom(referral, referer, reward, isAirdrop);
      distributed = distributed.add(reward);
      referer = _referralToReferer[referer];
    }

    poolReward = poolReward.add(forDistribution.sub(distributed));

    transferFrom(referral, _poolAccount, poolReward, isAirdrop);
  }

  function isHigher(
    uint256 index,
    uint256 stakesAmount,
    uint256 referralsCount,
    uint256 minReferralsStakesAmount
  ) internal view returns (bool) {
    return
      stakesAmount >= _refererLevels[index].minStakesAmount &&
      referralsCount >= _refererLevels[index].minReferrals &&
      minReferralsStakesAmount >= _refererLevels[index].minReferralsStakesAmount;
  }

  function someoneIsLower(
    uint256 index,
    uint256 stakesAmount,
    uint256 referralsCount,
    uint256 minReferralsStakesAmount
  ) internal view returns (bool) {
    return
      stakesAmount < _refererLevels[index].minStakesAmount ||
      referralsCount < _refererLevels[index].minReferrals ||
      minReferralsStakesAmount < _refererLevels[index].minReferralsStakesAmount;
  }

  function getSums(address referer, uint256 fromLevel, uint256 toLevel) internal view returns(uint256, uint256) {
    uint256 totalReferrals = 0;
    uint256 totalReferralsStakesSum = 0;
    for (uint256 i = fromLevel; i <= toLevel; i++) {
      totalReferrals = totalReferrals.add(_refererStats[referer][i].referralsCount);
      totalReferralsStakesSum = totalReferralsStakesSum.add(_refererStats[referer][i].totalActiveStakesSum);
    }
    return (totalReferrals, totalReferralsStakesSum);
  }

  function getRefererLevelIndex(address referer) internal view returns(uint256) {
    uint256 refererStakesSum = _refererStats[referer][0].totalActiveStakesSum;
    (uint256 totalReferrals, uint256 totalReferralsStakesSum) = getSums(referer, 1, 2);
    if (someoneIsLower(0, refererStakesSum, totalReferrals, totalReferralsStakesSum)) return 100;
    
    for (uint256 i = 0; i < _refererLevels.length; i++) {
      (totalReferrals, totalReferralsStakesSum) = getSums(referer, 1, _refererLevels[i].depth);
      bool isHigherCurrent = isHigher(i, refererStakesSum, totalReferrals, totalReferralsStakesSum);
      bool hasNextLevel = i + 1 < _refererLevels.length;
      bool someoneIsLowerNext = hasNextLevel && someoneIsLower(i + 1, refererStakesSum, totalReferrals, totalReferralsStakesSum);
      if ((isHigherCurrent && !hasNextLevel) || (isHigherCurrent && someoneIsLowerNext)) {
        return i;
      }
    }

    return 100;
  }

  /* \REF SECTION */
}
