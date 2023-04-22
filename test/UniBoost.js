const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");


function loadEnvVar(env, errorMsg) {
    if (env == undefined) {
        throw errorMsg;
    }

    return env;
}

function loadEnvVarInt(env, errorMsg) {
    if (env == undefined) {
        throw errorMsg;
    }

    return parseInt(env);
}

// setup uniswapV3 parameters
const testRpc = loadEnvVar(process.env.UNISWAP_TEST_RPC, "No UNISWAP_TEST_RPC");
const testBlock = loadEnvVarInt(process.env.UNISWAP_TEST_BLOCK, "No UNISWAP_TEST_BLOCK");
const testFactory = loadEnvVar(process.env.UNISWAP_TEST_FACTORY, "No UNISWAP_TEST_FACTORY");
const testNFT = loadEnvVar(process.env.UNISWAP_TEST_NFT, "No UNISWAP_TEST_NFT");
const testRouter = loadEnvVar(process.env.UNISWAP_TEST_ROUTER, "No UNISWAP_TEST_ROUTER");
const testFeeTier = loadEnvVarInt(process.env.UNISWAP_TEST_FEE_TIER, "No UNISWAP_TEST_FEE_TIER");

const UINT256_MAX = '0x' + 'f'.repeat(64);
const UINT128_MAX = '0x' + 'f'.repeat(32);
const UINT64_MAX = '0x' + 'f'.repeat(16);
const MIN_TICK = -887272;
const MAX_TICK = -MIN_TICK;

async function deployUniBoost() {
    // fork a testing environment
    await helpers.reset(testRpc, testBlock);

    // Contracts are deployed using the first signer/account by default
    const [owner, vault, project, user] = await ethers.getSigners();

    // deploy ERC20 tokens
    const MockToken = await ethers.getContractFactory("MockToken");
    const safeToken = await MockToken.connect(project).deploy("Safe Token", "SAFE", ethers.utils.parseEther('10000000'));
    const riskToken = await MockToken.connect(project).deploy("Risk Token", "RISK", ethers.utils.parseEther('10000000'));

    // deploy UniBoost
    const UniBoost = await ethers.getContractFactory("UniBoost");
    const uniBoost = await UniBoost.deploy(
        testFactory,
        testNFT,
        vault.address,
        10000,
        86400 * 30,
        3600,
        3600
    );

    // set up healthy assets
    await uniBoost.addHealthyAssets([ safeToken.address ]);

    const factory = await ethers.getContractAt("IUniswapV3Factory", testFactory);
    const nft = await ethers.getContractAt("INonfungiblePositionManager", testNFT);
    const router = await ethers.getContractAt("ISwapRouter", testRouter);

    // create a pool
    await factory.connect(project).createPool(safeToken.address, riskToken.address, testFeeTier);
    const pool = await ethers.getContractAt("IUniswapV3Pool", await factory.getPool(safeToken.address, riskToken.address, testFeeTier));
    await pool.connect(project).initialize(ethers.BigNumber.from(2).pow(96)); // initialize price = 1
    await pool.connect(project).increaseObservationCardinalityNext(300);
    const tickSpacing = await pool.tickSpacing();

    const minTick = Math.ceil(MIN_TICK / tickSpacing) * tickSpacing;
    const maxTick = Math.floor(MAX_TICK / tickSpacing) * tickSpacing;

    // provide liquidity for max range
    const token0 = safeToken.address < riskToken.address ? safeToken : riskToken;
    const token1 = safeToken.address > riskToken.address ? safeToken : riskToken;
    const amount = ethers.utils.parseEther('100000');
    await safeToken.connect(project).approve(nft.address, UINT256_MAX);
    await riskToken.connect(project).approve(nft.address, UINT256_MAX);
    await nft.connect(project).mint({
        token0: token0.address,
        token1: token1.address,
        fee: testFeeTier,
        tickLower: minTick,
        tickUpper: maxTick,
        amount0Desired: amount,
        amount1Desired: amount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: project.address,
        deadline: UINT64_MAX
    });

    // advance time for TWAP observation
    await helpers.time.increase(3600);

    return { owner, vault, project, user, uniBoost, factory, nft, router, pool, safeToken, riskToken, token0, token1 };
}

describe("UniBoost", function () {

    describe("Deployment", function() {
        it("Should set the parameters", async function () {
            const { uniBoost, vault, safeToken } = await helpers.loadFixture(deployUniBoost);

            expect(await uniBoost.factory()).to.equal(testFactory);
            expect(await uniBoost.v3PositionManager()).to.equal(testNFT);
            const feeConfig = await uniBoost.feeConfig();
            expect(feeConfig.protocolVault).to.equal(vault.address);
            expect(feeConfig.protocolFee).to.equal(10000);
            expect(await uniBoost.minBoostPeriod()).to.equal(86400 * 30);
            expect(await uniBoost.minStakedTimeForClaimingReward()).to.equal(3600);
            expect(await uniBoost.twapInterval()).to.equal(3600);

            expect(await uniBoost.getHealthyAssets()).to.eql([ safeToken.address ]);
        });
    });

    describe("Owner functions", function() {

    });

    describe("Project provider functions", function() {
        it("Should be able to create a boost pool", async function() {
            const { project, user, uniBoost, nft, router, pool, safeToken, riskToken, token0, token1 } = await helpers.loadFixture(deployUniBoost);

            const boostAmount = ethers.utils.parseEther('10000');
            const insuranceAmount = ethers.utils.parseEther('1000');

            // calculate insurance tick
            const insurancePrice = 0.05; // liquidate when price is less than 1 riskToken = 0.05 safeToken
            let insuranceTick = Math.floor(Math.log(insurancePrice) / Math.log(1.0001));
            if (token0.address != riskToken.address) {
                insuranceTick = -insuranceTick;                
            }

            const boostRate = 3000000;
            const block = await ethers.provider.getBlock('latest');
            const boostEndTime = block.timestamp + 86400 * 60;

            await riskToken.connect(project).approve(uniBoost.address, boostAmount);
            await safeToken.connect(project).approve(uniBoost.address, insuranceAmount);

            await uniBoost.connect(project).enableBoost(
                pool.address,
                boostAmount,
                insuranceAmount,
                insuranceTick,
                boostRate,
                boostEndTime
            );

            // transfer some fund to user
            const amount = ethers.utils.parseEther('100');
            await riskToken.connect(project).transfer(user.address, amount);
            await safeToken.connect(project).transfer(user.address, amount);

            // user creates a position
            const tickSpacing = await pool.tickSpacing();
            await riskToken.connect(user).approve(nft.address, UINT256_MAX);
            await safeToken.connect(user).approve(nft.address, UINT256_MAX);
            const priceRange = 0.9;
            const tickForPrice = Math.floor(Math.log(priceRange) / Math.log(1.0001));
            let minTick = tickForPrice > 0 ? -tickForPrice : tickForPrice;
            minTick = Math.floor(minTick / tickSpacing) * tickSpacing;
            let maxTick = -minTick;
            await nft.connect(user).mint({
                token0: token0.address,
                token1: token1.address,
                fee: testFeeTier,
                tickLower: minTick,
                tickUpper: maxTick,
                amount0Desired: amount,
                amount1Desired: amount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user.address,
                deadline: UINT64_MAX
            });

            const tokenId = await nft.tokenOfOwnerByIndex(user.address, 0);

            // user stake the position
            await nft.connect(user).setApprovalForAll(uniBoost.address, true);
            await uniBoost.connect(user).stakeLP(tokenId);
            //const lpStakeEvents = await uniBoost.queryFilter(uniBoost.filters.LPStaked(undefined, user.address));
            
            // simulate a swap
            const amountIn = ethers.utils.parseEther('100');
            await riskToken.connect(project).approve(router.address, UINT256_MAX);
            await safeToken.connect(project).approve(router.address, UINT256_MAX);
            await router.connect(project).exactInputSingle({
                tokenIn: riskToken.address,
                tokenOut: safeToken.address,
                fee: testFeeTier,
                recipient: project.address,
                deadline: UINT64_MAX,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // advance time
            await helpers.time.increase(3000);

            // check rewards, because staking time is not long enough
            // rewards should be 0
            const rewards = await uniBoost.connect(user).callStatic.claimReward(tokenId);
            expect(rewards.amount0).to.equal(0);
            expect(rewards.amount1).to.equal(0);
            expect(rewards.rewardAmount).to.equal(0);

            // advance time
            await helpers.time.increase(1000);

            // check rewards again
            const rewards2 = await uniBoost.connect(user).callStatic.claimReward(tokenId);
            let totalRewards;
            if (riskToken.address == token0.address) {
                expect(rewards2.amount0).to.not.equal(0);
                expect(rewards2.rewardAmount).to.equal(rewards2.amount0.mul(3));
                totalRewards = rewards2.amount0.add(rewards2.rewardAmount);
            }
            else {
                expect(rewards2.amount1).to.not.equal(0);
                expect(rewards2.rewardAmount).to.equal(rewards2.amount1.mul(3));
                totalRewards = rewards2.amount1.add(rewards2.rewardAmount);
            }

            // actually claim rewards
            const balanceBefore = await riskToken.balanceOf(user.address);
            await uniBoost.connect(user).claimReward(tokenId);
            const balanceAfter = await riskToken.balanceOf(user.address);
            expect(balanceAfter.sub(balanceBefore)).to.equal(totalRewards);

            // unstake lp
            await uniBoost.connect(user).unstakeLP(tokenId);
            expect(await nft.ownerOf(tokenId)).to.equal(user.address);

            // try to liquidate position
            await expect(uniBoost.liquidate(pool.address)).to.be.revertedWith("");

            // advance time beyond boost time
            await helpers.time.increase(86400 * 30);

            // close
            const riskBalanceBefore = await riskToken.balanceOf(project.address);
            const safeBalanceBefore = await safeToken.balanceOf(project.address);
            await uniBoost.connect(user).closeCurrentBoostRound(pool.address);
            const riskBalanceAfter = await riskToken.balanceOf(project.address);
            const safeBalanceAfter = await safeToken.balanceOf(project.address);

            expect(safeBalanceAfter.sub(safeBalanceBefore)).to.equal(insuranceAmount); // get insurance amount back
            expect(riskBalanceAfter.sub(riskBalanceBefore)).to.equal(boostAmount.mul(99).div(100).sub(rewards2.rewardAmount)); // get boost amount back (minus protocol fee and rewards claimed by user)
        });
    });
});
