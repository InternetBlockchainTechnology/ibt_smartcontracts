// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.8;

import "./lib/SafeMath.sol";
import "./lib/Moment.sol";
import "./lib/Pausable.sol";
import "./AccessControl.sol";
import "./interface/IERC20IBT.sol";
import "./ERC20/IERC20.sol";
import "./interface/IPoolManager.sol";
import "./interface/IPool.sol";
import "./interface/IPoolFactory.sol";
import "./interface/IPoolXPiFactory.sol";

contract PoolManager is IPoolManager, AccessControl {
  using SafeMath for uint256;

  uint256 _timelapsOffset = 0;

  IERC20IBT public _token;
  IPoolFactory public _poolFactory;
  IPoolXPiFactory public _poolXPiFactory;
  bool public _XPiCreated;

  address[] public _pools;
  mapping(address => bool) public _poolsTable;
  mapping(address => uint256) public _poolIndexTable;

  struct TeamProfitCalculatingMark {
    uint256 expiryFromTime;
    uint256 expiryTo;
    uint256 fromIndex;
    uint256 lastAggregatedBody;
  }

  struct TeamProfitMeta {
    uint256 lastMint;
    TeamProfitCalculatingMark mark;
    uint256[][] stakes;
  }

  mapping(uint256 => TeamProfitMeta) private _poolStakes;

  uint256[][] public _stakeProfitTable;
  uint256 public _initialStakeProfitTimestamp;
  uint256 public _initialStakeProfitPercent = 25;

  uint256 public _createPoolPrice = 1000 * 10 ** 18;

  address[] public _teamWallets;

  uint256 private _maxMintRewardIterations = 4000;

  constructor(
    IERC20IBT token,
    IPoolFactory poolFactory,
    IPoolXPiFactory poolXPiFactory
  ) {

    bytes4[] memory permissions = new bytes4[](2);
    permissions[0] = IPoolManager.pause.selector;
    permissions[1] = IPoolManager.mintTeamReward.selector;
    setAdditionalAdminPermissions(permissions);

    _token = token;
    _poolFactory = poolFactory;
    _poolXPiFactory = poolXPiFactory;
    createStakeProfitTable();

    _teamWallets.push(address(0));
    _teamWallets.push(address(0));
    _teamWallets.push(address(0));
    _teamWallets.push(address(0));
    _teamWallets.push(address(0));
  }

  modifier onlyPool() {
    require(_poolsTable[_msgSender()], "Only pool can call this function");
    _;
  }

  function pause(bool status) external onlyOwner {
    for (uint256 i = 0; i < _pools.length; i++) {
      IPool(_pools[i]).pause(status);
    }
  }

  function updateTeamWallet(address newWallet, uint256 index) external onlyOwner {
    emit TeamWalletChanged(index, newWallet);
    _teamWallets[index] = newWallet;
  }

  function getStakeProfitTable() external view returns (uint256[][] memory){
    return _stakeProfitTable;
  }

  function createStakeProfitTable() internal {
    require(_initialStakeProfitTimestamp == 0);
    _initialStakeProfitTimestamp = block.timestamp;

    for (uint256 fullYearsPassed = 0; fullYearsPassed < 10; fullYearsPassed++) {
      if (fullYearsPassed <= 10) {
        _stakeProfitTable.push(
          [
            Moment.addYears(_initialStakeProfitTimestamp.add(1), fullYearsPassed),
            Moment.addYears(_initialStakeProfitTimestamp, fullYearsPassed.add(1)),
            _initialStakeProfitPercent.sub(fullYearsPassed)
          ]
        );
      }
    }
    _stakeProfitTable.push(
      [
        Moment.addYears(_initialStakeProfitTimestamp, 11),
        Moment.addYears(_initialStakeProfitTimestamp, 21),
        _initialStakeProfitPercent.sub(10)
      ]
    );
    _stakeProfitTable.push(
      [
        Moment.addYears(_initialStakeProfitTimestamp + 1, 21),
        Moment.addYears(_initialStakeProfitTimestamp, 24),
        _initialStakeProfitPercent.sub(15)
      ]
    );
    uint256 threeCounter = 1;
    for (uint256 fullYearsPassed = 24; fullYearsPassed < 36; fullYearsPassed += 3) {
      _stakeProfitTable.push(
        [
          Moment.addYears(_initialStakeProfitTimestamp.add(1), fullYearsPassed),
          Moment.addYears(_initialStakeProfitTimestamp, fullYearsPassed.add(3)),
          _initialStakeProfitPercent.sub(15).sub(threeCounter)
        ]
      );
      threeCounter++;
    }
    _stakeProfitTable.push(
      [Moment.addYears(_initialStakeProfitTimestamp.add(1), 36), Moment.addYears(_initialStakeProfitTimestamp, 46), 5]
    );
  }

  function getCurrentStakeProfitPercent() external view returns (uint256) {
    uint256 percent = _initialStakeProfitPercent;
    for (uint8 i = 0; i < _stakeProfitTable.length; i++) {
      uint256 timestamp = block.timestamp;
      if (timestamp >= _stakeProfitTable[i][0] && timestamp <= _stakeProfitTable[i][1]) {
        percent = _stakeProfitTable[i][2];
        break;
      }
    }
    return percent;
  }

  /* Token proxy */

  function transferFrom(address from, address to, uint256 amount) external onlyPool {
    _token.poolManagerTransferFrom(from, to, amount);
  }

  function mint(address account, uint256 amount) external onlyPool {
    _token.poolManagerMint(account, amount);
  }

  function burn(address account, uint256 amount) external onlyPool {
    _token.poolManagerBurn(account, amount);
  }

  /* \Token proxy */

  /* Pool proxy */
 
  function appendStake(
    uint256 body,
    uint256 createdAt,
    uint256 expiriedAt
  ) external onlyPool {
    _poolStakes[_poolIndexTable[_msgSender()]].stakes.push([body, createdAt, expiriedAt]);
  }

  /* \Pool proxy */

  function createXPi(address owner, uint256 minStakeTokens, address poolAccount) external onlyOwner {
    require(!_XPiCreated);
    IPool pool = _poolXPiFactory.create(owner, IPoolManager(address(this)), minStakeTokens, poolAccount);

    _pools.push(address(pool));
    _poolsTable[address(pool)] = true;
    _poolIndexTable[address(pool)] = _pools.length - 1;

    emit PoolCreated(_pools.length - 1, 0);
  }
  
  function createPool(
    string memory name,
    string memory site,
    uint256 minStakeTokens,
    uint256[] memory refLevelsWithPercent,
    uint256 poolRefPercent,
    address poolAccount
  ) external {
    require(IERC20(address(_token)).balanceOf(_msgSender()) >= _createPoolPrice, "Insufficient balance to create a pool");

    _token.poolManagerBurn(_msgSender(), _createPoolPrice);

    IPool pool = _poolFactory.create(_msgSender(), IPoolManager(address(this)), name, site, minStakeTokens, refLevelsWithPercent, poolRefPercent, poolAccount);

    _pools.push(address(pool));
    _poolsTable[address(pool)] = true;
    _poolIndexTable[address(pool)] = _pools.length - 1;

    emit PoolCreated(_pools.length - 1, _createPoolPrice);
  }

  function calculateTotalReward(uint256 body, uint256 secondsPassed) private pure returns (uint256) {
    uint256 perFullPeriodProfit = body.mul(12).div(100);
    uint256 perSecondProfit = perFullPeriodProfit.mul(10000).div((30 days + 10 hours + 45 minutes) * 12);
    return secondsPassed.mul(perSecondProfit).div(10000);
  }

  function calculateTeamProfitForPool(uint256 poolIndex) private returns (uint256) {
    uint256 totalReward = 0;
    TeamProfitMeta storage meta = _poolStakes[poolIndex];
    if (meta.stakes.length == 0) return totalReward;
    uint256 i = 0;
    uint256 currentTimestamp = block.timestamp;

    if (currentTimestamp > meta.stakes[meta.mark.expiryTo][1]) {
      i = meta.mark.expiryTo;
    } else {
      i = meta.mark.fromIndex;
    }

    uint256 secondsPassed = 0;

    if (meta.mark.lastAggregatedBody > 0 && currentTimestamp < meta.mark.expiryFromTime) {
      secondsPassed = Moment.diffSeconds(meta.lastMint, currentTimestamp);
      totalReward = totalReward.add(calculateTotalReward(meta.mark.lastAggregatedBody, secondsPassed));
    }

    for (i; i < meta.stakes.length; i++) {
      bool lastIsExpiried = false;

      if (currentTimestamp < meta.stakes[i][2]) {
        if (lastIsExpiried && meta.mark.lastAggregatedBody > 0) {
          secondsPassed = Moment.diffSeconds(meta.lastMint, currentTimestamp);
          totalReward = totalReward.add(calculateTotalReward(meta.mark.lastAggregatedBody, secondsPassed));
        }

        if (i < meta.mark.fromIndex) {
          i = meta.mark.fromIndex;
        }
        if (i == meta.stakes.length) break;

        uint256 from = meta.lastMint > meta.stakes[i][1] ? meta.lastMint : meta.stakes[i][1];
        secondsPassed = Moment.diffSeconds(from, currentTimestamp);
        totalReward = totalReward.add(calculateTotalReward(meta.stakes[i][0], secondsPassed));
        meta.mark.fromIndex = i + 1;
        meta.mark.lastAggregatedBody = meta.mark.lastAggregatedBody.add(meta.stakes[i][0]);
        if (meta.mark.expiryFromTime == 0 || meta.mark.expiryFromTime > meta.stakes[i][2]) {
          meta.mark.expiryFromTime = meta.stakes[i][2];
        }
      } else {
        meta.mark.expiryTo = i + 1;
        secondsPassed = Moment.diffSeconds(meta.lastMint, meta.stakes[i][2]);
        totalReward = totalReward.add(calculateTotalReward(meta.stakes[i][0], secondsPassed));
        if (meta.mark.lastAggregatedBody > 0) {
          meta.mark.lastAggregatedBody = meta.mark.lastAggregatedBody.sub(meta.stakes[i][0]);
        }
        lastIsExpiried = true;
      }
    }

    return totalReward;
  }

  function getCurrentTeamProfitForPool(uint256 poolIndex) public view returns (uint256) {
    uint256 totalReward = 0;
    TeamProfitMeta storage meta = _poolStakes[poolIndex];
    if (meta.stakes.length == 0) return totalReward;
    uint256 i = 0;
    uint256 currentTimestamp = block.timestamp;

    if (currentTimestamp > meta.stakes[meta.mark.expiryTo][1]) {
      i = meta.mark.expiryTo;
    } else {
      i = meta.mark.fromIndex;
    }

    uint256 secondsPassed = 0;

    if (meta.mark.lastAggregatedBody > 0 && currentTimestamp < meta.mark.expiryFromTime) {
      secondsPassed = Moment.diffSeconds(meta.lastMint, currentTimestamp);
      totalReward = totalReward.add(calculateTotalReward(meta.mark.lastAggregatedBody, secondsPassed));
    }

    uint256 iterations = 0;

    for (i; i < meta.stakes.length; i++) {
      iterations++;
      if (iterations > _maxMintRewardIterations) break;

      bool lastIsExpiried = false;

      if (currentTimestamp < meta.stakes[i][2]) {
        if (lastIsExpiried && meta.mark.lastAggregatedBody > 0) {
          secondsPassed = Moment.diffSeconds(meta.lastMint, currentTimestamp);
          totalReward = totalReward.add(calculateTotalReward(meta.mark.lastAggregatedBody, secondsPassed));
        }

        if (i < meta.mark.fromIndex) {
          i = meta.mark.fromIndex;
        }
        if (i == meta.stakes.length) break;

        uint256 from = meta.lastMint > meta.stakes[i][1] ? meta.lastMint : meta.stakes[i][1];
        secondsPassed = Moment.diffSeconds(from, currentTimestamp);
        totalReward = totalReward.add(calculateTotalReward(meta.stakes[i][0], secondsPassed));
      } else {
        secondsPassed = Moment.diffSeconds(meta.lastMint, meta.stakes[i][2]);
        totalReward = totalReward.add(calculateTotalReward(meta.stakes[i][0], secondsPassed));
        lastIsExpiried = true;
      }
    }

    return totalReward;
  }

  function getCurrentTeamProfit() external view returns (uint256) {
    uint256 totalTeamProfit = 0;
    for (uint256 i = 0; i < _pools.length; i++) {
      uint256 profit = getCurrentTeamProfitForPool(i);
      if (profit == 0) continue;
      totalTeamProfit = totalTeamProfit.add(profit);
    }
    return totalTeamProfit;
  }

  function distributeTeamProfitForPool(uint256 teamProfit) internal {
    uint256 teamProfitPart = teamProfit.div(5);
    uint256 teamProfitRemainder = teamProfit.sub(teamProfitPart);
    for (uint8 i = 0; i < _teamWallets.length; i++) {
      uint256 reward = i == 0 ? teamProfitPart.add(teamProfitRemainder) : teamProfitPart;
      _token.poolManagerMint(_teamWallets[i], reward);
    }
  }

  function setMaxMintRewardIterations(uint256 count) external onlyOwner {
    _maxMintRewardIterations = count;
  }

  function mintTeamReward() external checkAccess(IPoolManager.mintTeamReward.selector) returns(uint256) {
    uint256 totalReward = 0;
    for (uint256 i = 0; i < _pools.length; i++) {
      uint256 teamProfit = calculateTeamProfitForPool(i);
      if (teamProfit == 0) continue;
      _poolStakes[i].lastMint = block.timestamp;
      distributeTeamProfitForPool(teamProfit);
      totalReward = totalReward.add(teamProfit);
    }
    return totalReward;
  }
}