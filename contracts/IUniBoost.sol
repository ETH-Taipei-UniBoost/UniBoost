//SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniBoost {
    error InvalidFeeConfig();
    error InvalidBoostAmountOrRate();
    error InvalidTriggerCondition();
    error NotAValidPool();
    error BoostTimeTooShort();
    error BoostRoundNotEnd();
    error PoolBoostNotActive();
    error NotIncentivizer();
    error InsuranceTriggered();
    error InvalidTime();
    error liquidateConditionNotMet();
    error liquidateConditionMet();
    error NotTokenOwner();


    event MinBoostPeriodSet(uint256 indexed minBoostPeriod);
    event MinStakedTimeForClaimingRewardSet(uint256 indexed minStakedTimeForClaimingReward);
    event FeeConfigSet(address protocolVault, uint24 protocolFee);
    event HealthAssetsChanged();
    event BoostEnabled(
        address indexed pool,
        uint256 increasedBoostAmount,
        uint256 insuranceAmount,
        int24 insuranceTriggerPriceInTick,
        uint32 boostRate,
        uint64 indexed boostEndTime
    );
    event FundAdded(
        address indexed pool,
        uint256 indexed increasedBoostAmount, 
        uint256 indexed insuranceAmount,
        uint256 protocolFee
    );
    event FundRemoved(
        address indexed pool,
        uint256 indexed boostRewardBalance,
        uint256 indexed insuranceBalance
    );
    event BoostLiquidated(uint256 indexed timestamp);
    event BoostClosed(uint256 indexed timestamp);
    event LPStaked(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed stakedTime,
        address pool,
        uint256 insuranceWeight
    );
    event LPUnstaked(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed unstakedTime,
        address pool,
        uint256 rewardAmount,
        uint256 insuranceAmount
    );
    event FeeCollect(uint256 indexed tokenId, address indexed collectFor, uint256 amount0, uint256 amount1);
    event RewardClaimed(uint256 tokenId, address owner, uint256 claimdTime, address pool, uint256 rewardAmount);
    event InsuranceClaimed(uint256 tokenId, address owner, uint256 claimdTime, address pool, uint256 insuranceAmount);

    enum RoundStatus {
        closed,
        active,
        insuranceTriggered
    }

    struct FeeConfig {
        address protocolVault;
        uint24 protocolFee;
    }

    struct PoolInfo {
        bool initialized;
        uint24 fee;
        IERC20 healthToken;
        IERC20 pairedToken;
        bool isToken0Healthy;
        bool isToken1Healthy;
    }

    struct BoostRoundData {
        RoundStatus status;
        address incentivizer;
        uint64 boostEndTime;
        uint32 boostRate;
        int24 insuranceTriggerPriceInTick;
        uint256 boostRewardBalance;
        uint256 insuranceBalance;
        uint256 totalInsuranceWeight;
    }

    struct StakedTokenInfo {
        address owner;
        uint64 stakedTime;
        address pool;
        uint64 lastClaimTime;
        uint256 insuranceWeight;
    }

    // for incentivizer
    function enableBoost(
        address _pool,
        uint256 _boostAmount,
        uint256 _insuranceAmount,
        int24 _insuranceTriggerPriceInTick,
        uint32 _boostRate,
        uint64 _boostEndTime
    ) external returns (uint256 increasedBoostAmount);
    function addFund(
        address _pool,
        uint256 _rewardAmount,
        uint256 _insuranceAmount
    ) external returns (uint256 increasedBoostAmount);

    // for liquidity provider
    function stakeLP(uint256 _tokenId) external returns (uint256 insuranceWeight);
    function unstakeLP(uint256 _tokenId) external returns (
        uint256 amount0,
        uint256 amount1,
        uint256 rewardAmount,
        uint256 insuranceAmount  
    );
    function claimReward(uint256 _tokenId) external returns (
        uint256 amount0,
        uint256 amount1,
        uint256 rewardAmount
    );
    function claimOwedInsurance(uint256 _tokenId) external returns (uint256 insuranceAmount);

    // everyone can do this after the price hits the insurance trigger
    function liquidate(address _pool) external;
    // everyone can close boost round if there's no boosting reward fot the pool
    function closeCurrentBoostRound(address _pool) external;
}
