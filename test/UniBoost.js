const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { providers } = require("ethers");
const { network, ethers, upgrades } = require("hardhat");


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
const UINT64_MAX = '0x' + 'f'.repeat(16);

async function deployUniBoost() {
    // fork a testing environment
    await helpers.reset(testRpc, testBlock);

    // Contracts are deployed using the first signer/account by default
    const [owner, vault, user] = await ethers.getSigners();

    // deploy ERC20 tokens
    const MockToken = await ethers.getContractFactory("MockToken");
    const safeToken = await MockToken.deploy("Safe Token", "SAFE", ethers.utils.parseEther('10000000'));
    const riskToken = await MockToken.deploy("Risk Token", "RISK", ethers.utils.parseEther('10000000'))

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

    const factory = await ethers.getContractAt("IUniswapV3Factory", testFactory);
    const nft = await ethers.getContractAt("INonfungiblePositionManager", testNFT);

    return { owner, vault, user, uniBoost, factory, nft, safeToken, riskToken };
}

describe("UniBoost", function () {

    describe("Deployment", function() {
        it("Should set the parameters", async function () {
            const { uniBoost } = await helpers.loadFixture(deployUniBoost);

            expect(await uniBoost.minBoostPeriod()).to.equal(86400 * 30);
            expect(await uniBoost.minStakedTimeForClaimingReward()).to.equal(3600);
            expect(await uniBoost.twapInterval()).to.equal(3600);
        });
    });
});
