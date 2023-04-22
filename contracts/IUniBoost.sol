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
    ) external;
    function addFund(address _pool, uint256 _rewardAmount, uint256 _insuranceAmount) external;

    // for liquidity provider
    function stakeLP(uint256 _tokenId) external;
    function unstakeLP(uint256 _tokenId) external;
    function claimReward(uint256 _tokenId) external;
    function claimOwedInsurance(uint256 _tokenId) external;

    // everyone can do this after the price hits the insurance trigger
    function liquidate(address _pool) external;
    // everyone can close boost round if there's no boosting reward fot the pool
    function closeCurrentBoostRound(address _pool) external;
}
