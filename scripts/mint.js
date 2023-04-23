const { ethers } = require("hardhat");

const UINT64_MAX = '0x' + 'f'.repeat(16);

async function main() {
    [owner] = await ethers.getSigners();

    const rkt = await ethers.getContractAt("MockToken", "0xd5c3b7B3fC63c05593ce7DB91d6C4dE776a208eB");
    const dai = await ethers.getContractAt("MockToken", "0x2C149B0a04b6018982221f2063Eea1838a3dD0a6");
    const nft = await ethers.getContractAt("INonfungiblePositionManager", "0xFc3d86E2F5cd3d82f488735E4D163AcE5Cfaa3e3");
    const minTick = -1080;
    const maxTick = 1080;
    const amount = ethers.utils.parseEther("100");
    await nft.mint({
        token0: dai.address,
        token1: rkt.address,
        fee: 3000,
        tickLower: minTick,
        tickUpper: maxTick,
        amount0Desired: amount,
        amount1Desired: amount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: "0x7c5A895b3B0Bcdf89AD3c49C58100d5a653fdfb6",
        deadline: UINT64_MAX
    }, { gasPrice: 8 });
}

main()
.then(res => process.exit(0))
.catch(err => console.error(err));
