//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import "./IUniBoost.sol";

contract UniBoost is IUniBoost, Ownable, ReentrancyGuard, IERC721Receiver {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using FullMath for uint256;

    uint256 public minBoostPeriod;
    uint256 public minStakedTimeForClaimingReward;
    uint32 public immutable twapInterval;
    
    IUniswapV3Factory public immutable factory;
    INonfungiblePositionManager public immutable v3PositionManaer;
    FeeConfig public feeConfig;
    EnumerableSet.AddressSet healthyAssets;

    // address => PoolInfo
    mapping (address => PoolInfo) public poolInfoMap;

    // pool => BoostRound
    mapping (address => BoostRoundData[]) public poolRoundDataMap;

    // owner => tokenIds
    mapping (address => EnumerableSet.UintSet) stakedV3TokenIdsMap;

    // positionTokenId => StakedTokenInfo
    mapping (uint256 => StakedTokenInfo) public stakedTokenInfoMap;
    
    constructor(
        address _factory,
        address _nonfungiblePositionManager,
        address _protocolVault,
        uint24 _protocolFee,
        uint256 _minBoostPeriod,
        uint256 _minStakedTimeForClaimingReward,
        uint32 _twapInterval
    ) {
        factory = IUniswapV3Factory(_factory);
        v3PositionManaer = INonfungiblePositionManager(_nonfungiblePositionManager);
        _setFeeConfig(_protocolVault, _protocolFee);
        _setMinBoostPeriod(_minBoostPeriod);
        _setMinStakedTimeForClaimingReward(_minStakedTimeForClaimingReward);
        twapInterval = _twapInterval;
    }

    function setMinBoostPeriod(uint256 _minBoostPeriod) external onlyOwner {
        _setMinBoostPeriod(_minBoostPeriod);
    }

    function _setMinBoostPeriod(uint256 _minBoostPeriod) internal {
        minBoostPeriod = _minBoostPeriod;

        emit MinBoostPeriodSet(_minBoostPeriod);
    }

    function setMinStakedTimeForClaimingReward(uint256 _minStakedTimeForClaimingReward) external onlyOwner {
        _setMinStakedTimeForClaimingReward(_minStakedTimeForClaimingReward);
    }

    function _setMinStakedTimeForClaimingReward(uint256 _minStakedTimeForClaimingReward) internal {
        minStakedTimeForClaimingReward = _minStakedTimeForClaimingReward;

        emit MinStakedTimeForClaimingRewardSet(_minStakedTimeForClaimingReward);
    }

    function setFeeConfig(address _protocolVault, uint24 _protocolFee) external onlyOwner {
        _setFeeConfig(_protocolVault, _protocolFee);
    }

    function _setFeeConfig(address _protocolVault, uint24 _protocolFee) internal {
        if (_protocolFee > 1000000) revert InvalidFeeConfig();
        feeConfig = FeeConfig({
            protocolVault: _protocolVault,
            protocolFee: _protocolFee
        });

        emit FeeConfigSet(_protocolVault, _protocolFee);
    }

    function addHealthyAssets(address[] calldata _assets) external onlyOwner {
        for (uint i = 0; i < _assets.length; i++) {
            healthyAssets.add(_assets[i]);
        }

        emit HealthyAssetsChanged(true, _assets);
    }

    function removeHealthyAssets(address[] calldata _assets) external onlyOwner {
        for (uint i = 0; i < _assets.length; i++) {
            healthyAssets.remove(_assets[i]);
        }

        emit HealthyAssetsChanged(false, _assets);
    }

    function getHealthyAssets() external view returns (address[] memory assets) {
        return healthyAssets.values();
    }

    function getNumberOfHealhyAssets() external view returns (uint256 length) {
        return healthyAssets.length();
    }

    function getHealhyAssetsAt(uint256 _index) external view returns (address asset) {
        return healthyAssets.at(_index);
    }

    function enableBoost(
        address _pool,
        uint256 _boostAmount,
        uint256 _insuranceAmount,
        int24 _insuranceTriggerPriceInTick,
        uint32 _boostRate,
        uint64 _boostEndTime
    ) external nonReentrant returns (uint256 increasedBoostAmount) {
        if (_boostAmount == 0 || _boostRate == 0) revert InvalidBoostAmountOrRate();
        if (_boostEndTime < block.timestamp + minBoostPeriod) revert BoostTimeTooShort();

        uint256 boostRoundDataLength = poolRoundDataMap[_pool].length;
        PoolInfo storage poolInfo = poolInfoMap[_pool];

        if (poolInfo.initialized) {
            if (boostRoundDataLength != 0) {
                BoostRoundData storage boostRoundData = poolRoundDataMap[_pool][boostRoundDataLength - 1];
                if (boostRoundData.status == RoundStatus.active) {
                    if (boostRoundData.boostEndTime >= block.timestamp) revert BoostRoundNotEnd();
                    _removeFund(_pool, poolInfo, boostRoundData);
                }
                if (boostRoundData.status == RoundStatus.insuranceTriggered) revert InsuranceTriggered();
            }
        }
        else {
            (
                bool isValidBoostPool,
                uint24 fee,
                address token0,
                address token1,
                bool isToken0Healthy,
                bool isToken1Healthy
            ) = _getPoolInfo(_pool);

            if (!isValidBoostPool) revert NotAValidPool();
            if (factory.getPool(token0, token1, fee) != _pool) revert NotAValidPool();

            int24 twap;
            if (isToken0Healthy && _insuranceTriggerPriceInTick <= twap) revert InvalidTriggerCondition();
            if (isToken0Healthy && _insuranceTriggerPriceInTick <= twap) revert InvalidTriggerCondition();

            (IERC20 healthyToken, IERC20 pairedToken) = isToken0Healthy ?
                (IERC20(token0), IERC20(token1)):
                (IERC20(token1), IERC20(token0));

            poolInfoMap[_pool] = PoolInfo({
                initialized: true,
                fee: fee,
                healthyToken: healthyToken,
                pairedToken: pairedToken,
                isToken0Healthy: isToken0Healthy,
                isToken1Healthy: isToken1Healthy
            });
        }

        (increasedBoostAmount, ) = _addFund(_pool, poolInfo, _boostAmount, _insuranceAmount);

        poolRoundDataMap[_pool].push(BoostRoundData({
            status: RoundStatus.active,
            incentivizer: msg.sender,
            boostEndTime: _boostEndTime,
            boostRate: _boostRate,
            insuranceTriggerPriceInTick: _insuranceTriggerPriceInTick,
            boostRewardBalance: increasedBoostAmount,
            totalInsuranceWeight: 0,
            insuranceBalance: _insuranceAmount
        }));

        emit BoostEnabled(
            _pool,
            increasedBoostAmount,
            _insuranceAmount,
            _insuranceTriggerPriceInTick,
            _boostRate,
            _boostEndTime
        );
    }

    function addFund(
        address _pool,
        uint256 _amount,
        uint256 _insuranceAmount
    ) external nonReentrant returns (uint256 increasedBoostAmount) {
        if (_amount == 0) revert InvalidBoostAmountOrRate();
        
        uint256 boostRoundDataLength = poolRoundDataMap[_pool].length;
        if (boostRoundDataLength == 0) revert PoolBoostNotActive();
        PoolInfo storage poolInfo = poolInfoMap[_pool];
        BoostRoundData storage boostRoundData = _checkBoostActiveAndGetRoundData(_pool);

        if (boostRoundData.incentivizer != msg.sender) revert NotIncentivizer(); 

        (increasedBoostAmount, ) = _addFund(_pool, poolInfo, _amount, _insuranceAmount);
        boostRoundData.boostRewardBalance += increasedBoostAmount;

        if(_insuranceAmount != 0) {
            boostRoundData.insuranceBalance += _insuranceAmount;
        }
    }

    function liquidate(address _pool) external {
        (bool met, , ) = _checkLiquidateCondition(_pool);
        if (!met) revert liquidateConditionNotMet();

        emit BoostLiquidated(block.timestamp);
    }

    function closeCurrentBoostRound(address _pool) external {
        (bool met, bool isActive, BoostRoundData storage boostRoundData) = _checkLiquidateCondition(_pool);
        
        if (met) revert liquidateConditionMet();
        if (isActive) {
            _removeFund(_pool, poolInfoMap[_pool], boostRoundData);
            boostRoundData.status = RoundStatus.closed;
        }

        emit BoostClosed(block.timestamp);
    }

    function getPoolInfo(address _pool) external view returns (
        bool isValidBoostPool,
        uint24 fee,
        address token0,
        address token1,
        bool isToken0Healthy,
        bool isToken1Healthy
    ) {
        return _getPoolInfo(_pool);
    }

    function stakeLP(uint256 _tokenId) external nonReentrant returns (uint256 insuranceWeight) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower, 
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            , 
        ) = v3PositionManaer.positions(_tokenId);
        address pool = factory.getPool(token0, token1, fee);
        BoostRoundData storage boostRoundData = _checkBoostActiveAndGetRoundData(pool);
        v3PositionManaer.safeTransferFrom(msg.sender, address(this), _tokenId);
        _collectFor(_tokenId, msg.sender);

        PoolInfo storage poolInfo = poolInfoMap[pool];
        int24 twap = _getTwap(pool);
        int24 tickLiquidation = boostRoundData.insuranceTriggerPriceInTick;
        uint160 ratioTwap = TickMath.getSqrtRatioAtTick(twap);
     
        if (poolInfo.isToken0Healthy && twap < tickUpper) {
            insuranceWeight = tickLiquidation > tickUpper ?
                _getAmount0ForLiquidity(ratioTwap, TickMath.getSqrtRatioAtTick(tickUpper), liquidity) :
                _getAmount0ForLiquidity(ratioTwap, TickMath.getSqrtRatioAtTick(tickLiquidation), liquidity);
        }

        if (poolInfo.isToken1Healthy && twap > tickLower) {
            insuranceWeight = tickLiquidation < tickLower ?
                _getAmount1ForLiquidity(TickMath.getSqrtRatioAtTick(tickLower), ratioTwap, liquidity):
                _getAmount1ForLiquidity(TickMath.getSqrtRatioAtTick(tickLiquidation), ratioTwap, liquidity);
        }

        if (insuranceWeight > 0) {
            boostRoundData.totalInsuranceWeight += insuranceWeight;
        }
        stakedTokenInfoMap[_tokenId] = StakedTokenInfo({
            owner: msg.sender,
            stakedTime: uint64(block.timestamp),
            pool: pool,
            lastClaimTime: uint64(block.timestamp),
            insuranceWeight: insuranceWeight
        });

        emit LPStaked(_tokenId, msg.sender, block.timestamp, pool, insuranceWeight);
    }

    function unstakeLP(uint256 _tokenId) external returns (
        uint256 amount0,
        uint256 amount1,
        uint256 rewardAmount,
        uint256 insuranceAmount  
    ) {
        StakedTokenInfo storage stakedTokenInfo = stakedTokenInfoMap[_tokenId];
        if (stakedTokenInfo.owner != msg.sender) revert NotTokenOwner();
        address pool = stakedTokenInfo.pool;
        uint256 boostRoundDataLength = poolRoundDataMap[pool].length;
        BoostRoundData storage boostRoundData = poolRoundDataMap[pool][boostRoundDataLength - 1];
        PoolInfo storage poolInfo = poolInfoMap[pool];

        if (
            boostRoundData.status == RoundStatus.insuranceTriggered ||
            stakedTokenInfo.lastClaimTime + minStakedTimeForClaimingReward >= block.timestamp
        ) {
            (
                amount0,
                amount1,
                rewardAmount
            ) = _claimReward(pool, _tokenId, stakedTokenInfo, poolInfo, boostRoundData);
        }

        if (boostRoundData.status == RoundStatus.insuranceTriggered) {
            insuranceAmount = _claimOwedInsurance(_tokenId, stakedTokenInfo, boostRoundData);
        }
        
        v3PositionManaer.safeTransferFrom(address(this), msg.sender, _tokenId);

        delete stakedTokenInfoMap[_tokenId];

        emit LPUnstaked(_tokenId, msg.sender, block.timestamp, pool, rewardAmount, insuranceAmount);
    }

    function claimReward(uint256 _tokenId) external nonReentrant returns (
        uint256 amount0,
        uint256 amount1,
        uint256 rewardAmount
    ) {
        StakedTokenInfo storage stakedTokenInfo = stakedTokenInfoMap[_tokenId];
        if (stakedTokenInfo.owner != msg.sender) revert NotTokenOwner();
        address pool = stakedTokenInfo.pool;
        PoolInfo storage poolInfo = poolInfoMap[pool];
        BoostRoundData storage boostRoundData = _checkBoostActiveAndGetRoundData(stakedTokenInfo.pool);

        if (
            boostRoundData.status == RoundStatus.insuranceTriggered ||
            stakedTokenInfo.lastClaimTime + minStakedTimeForClaimingReward >= block.timestamp
        ) {
            (
                amount0,
                amount1,
                rewardAmount
            ) = _claimReward(pool, _tokenId, stakedTokenInfo, poolInfo, boostRoundData);
        }
    }

    function claimOwedInsurance(uint256 _tokenId) external returns (uint256 insuranceAmount) {
        StakedTokenInfo storage stakedTokenInfo = stakedTokenInfoMap[_tokenId];
        if (stakedTokenInfo.owner != msg.sender) revert NotTokenOwner();

        uint256 boostRoundDataLength = poolRoundDataMap[stakedTokenInfo.pool].length;
        BoostRoundData storage boostRoundData = poolRoundDataMap[stakedTokenInfo.pool][boostRoundDataLength - 1];
        if (boostRoundData.status != RoundStatus.insuranceTriggered) revert liquidateConditionNotMet();

        insuranceAmount = _claimOwedInsurance(_tokenId, stakedTokenInfo, boostRoundData);
    }

    function _addFund(
        address _pool,
        PoolInfo storage _poolInfo,
        uint256 _boostAmount,
        uint256 _insuranceAmount
    ) internal returns (
        uint256 increasedBoostAmount,
        uint256 protocolFee
    ) {
        if (_boostAmount != 0) {
            protocolFee = _boostAmount.mulDivRoundingUp(feeConfig.protocolFee, 1000000);
            increasedBoostAmount = _boostAmount - protocolFee;

            _poolInfo.pairedToken.safeTransferFrom(msg.sender, address(this), _boostAmount);
            _poolInfo.pairedToken.safeTransfer(feeConfig.protocolVault, protocolFee);
        }

        if (_insuranceAmount != 0) {
            _poolInfo.healthyToken.safeTransferFrom(msg.sender, address(this), _insuranceAmount);
        }

        emit FundAdded(_pool, increasedBoostAmount, _insuranceAmount, protocolFee);
    }

    function _removeFund(
        address _pool,
        PoolInfo storage _poolInfo,
        BoostRoundData storage _boostRoundData
    ) internal {
        address receiver = _boostRoundData.incentivizer;
        _poolInfo.pairedToken.safeTransfer(receiver, _boostRoundData.boostRewardBalance);
        _poolInfo.healthyToken.safeTransfer(receiver, _boostRoundData.insuranceBalance);
        _boostRoundData.status = RoundStatus.closed;

        emit FundRemoved(_pool, _boostRoundData.boostRewardBalance, _boostRoundData.insuranceBalance);
    }

    function _checkBoostActiveAndGetRoundData(address _pool) internal view returns (
        BoostRoundData storage boostRoundData
    ) {
        uint256 boostRoundDataLength = poolRoundDataMap[_pool].length;
        if (boostRoundDataLength == 0) revert PoolBoostNotActive();
        boostRoundData = poolRoundDataMap[_pool][boostRoundDataLength - 1];
        
        if (
            boostRoundData.status != RoundStatus.active ||
            boostRoundData.boostEndTime < block.timestamp
        ) revert PoolBoostNotActive();
    }

    function _checkLiquidateCondition(address _pool) internal returns (
        bool met,
        bool isActive,
        BoostRoundData storage boostRoundData
    ) {
        boostRoundData = _checkBoostActiveAndGetRoundData(_pool);
        PoolInfo storage poolInfo = poolInfoMap[_pool];
        int24 twap = _getTwap(_pool);
        if (
            (poolInfo.isToken0Healthy && twap < boostRoundData.insuranceTriggerPriceInTick) ||
            (poolInfo.isToken1Healthy && twap > boostRoundData.insuranceTriggerPriceInTick)
        ) return (false, true, boostRoundData);

        boostRoundData.status = RoundStatus.insuranceTriggered;
        return (true, false, boostRoundData);
    }

    function _getPoolInfo(address _pool) internal view returns (
        bool isValidBoostPool,
        uint24 fee,
        address token0,
        address token1,
        bool isToken0Healthy,
        bool isToken1Healthy
    ) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
        isToken0Healthy = healthyAssets.contains(token0);
        isToken1Healthy = healthyAssets.contains(token1);
        isValidBoostPool = isToken0Healthy != isToken1Healthy;
    }

    function _getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) internal pure returns (uint256 amount0) {
        return (
            uint256(liquidity) << FixedPoint96.RESOLUTION
        ).mulDiv(sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96) / sqrtRatioAX96;
    }

    function _getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) internal pure returns (uint256 amount1) {
        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    function _getTwap(address _pool) internal view returns (int24 twapInTick) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = twapInterval;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(_pool).observe(secondsAgo);

        return int24((tickCumulatives[1] - tickCumulatives[0]) / int64(uint64(twapInterval)));
    }

    function _claimReward(
        address pool,
        uint256 _tokenId,
        StakedTokenInfo storage _stakedTokenInfo,
        PoolInfo storage _poolInfo,
        BoostRoundData storage _boostRoundData
    ) internal returns (uint256 amount0, uint256 amount1, uint256 rewardAmount) {
        (amount0, amount1) = _collectFor(_tokenId, _stakedTokenInfo.owner);

        rewardAmount = (_poolInfo.isToken0Healthy ? amount1 : amount0).mulDiv(_boostRoundData.boostRate, 1000000);
        rewardAmount = (rewardAmount > _boostRoundData.boostRewardBalance ? _boostRoundData.boostRewardBalance : rewardAmount);
        if (rewardAmount == 0) return (rewardAmount, amount0, amount1);

        _poolInfo.pairedToken.safeTransfer(_stakedTokenInfo.owner, rewardAmount);
        _stakedTokenInfo.lastClaimTime = uint64(block.timestamp);
        _boostRoundData.boostRewardBalance -= rewardAmount;

        emit RewardClaimed(_tokenId, msg.sender, block.timestamp, pool, rewardAmount);
    }

    function _collectFor(uint256 _tokenId, address _recipient) internal returns (
        uint256 amount0,
        uint256 amount1
    ) {
        (amount0, amount1) = v3PositionManaer.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: _recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit FeeCollect(_tokenId, _recipient, amount0, amount1);
    }

    function _claimOwedInsurance(
        uint256 _tokenId,
        StakedTokenInfo storage _stakedTokenInfo,
        BoostRoundData storage _boostRoundData
    ) internal returns (uint256 amount) {
        PoolInfo storage poolInfo = poolInfoMap[_stakedTokenInfo.pool];
        amount = _boostRoundData.insuranceBalance.mulDiv(
            _stakedTokenInfo.insuranceWeight,
            _boostRoundData.totalInsuranceWeight
        );
        poolInfo.healthyToken.safeTransfer(msg.sender, amount);
        _stakedTokenInfo.insuranceWeight = 0;
        _boostRoundData.insuranceBalance -= amount;

        emit InsuranceClaimed(_tokenId, msg.sender, block.timestamp, _stakedTokenInfo.pool, amount);
    }

    // IERC721Receiver
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}