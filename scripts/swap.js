const { ethers } = require("hardhat");

const UINT64_MAX = '0x' + 'f'.repeat(16);

async function main() {
    [owner] = await ethers.getSigners();

    const rkt = await ethers.getContractAt("MockToken", "0xd5c3b7B3fC63c05593ce7DB91d6C4dE776a208eB");
    const dai = await ethers.getContractAt("MockToken", "0x2C149B0a04b6018982221f2063Eea1838a3dD0a6");
    const router = await ethers.getContractAt("ISwapRouter", "0x04FDF3C67525AbFFa9D56fA972cA0aa79c1b0455");
    const amount = ethers.utils.parseEther("100");

    await router.exactInputSingle({
        tokenIn: rkt.address,
        tokenOut: dai.address,
        fee: 3000,
        recipient: owner.address,
        deadline: UINT64_MAX,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    }, { gasPrice: 8 });

    await router.exactInputSingle({
        tokenIn: dai.address,
        tokenOut: rkt.address,
        fee: 3000,
        recipient: owner.address,
        deadline: UINT64_MAX,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    }, { gasPrice: 8 });
}

main()
.then(res => process.exit(0))
.catch(err => console.error(err));
