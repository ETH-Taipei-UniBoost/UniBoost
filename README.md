# UniBoost

### [Contract (this repo)](https://github.com/ETH-Taipei-UniBoost/UniBoost) | [Frontend](https://github.com/ETH-Taipei-UniBoost/React-UniBoost) | [Doc](https://github.com/ETH-Taipei-UniBoost/Doc)

### Overview:

A Trustless and Permissionless Liquidity Mining Tool with insurance protection for Uniswap v3

-   Incentivizers enable boosting program, providing rewards and insurance for liquidity providers.
-   Incentivizers aim to boost liquidity of a specific token A,
    paired with a health asset H.
-   Rewards distributed proportionally to trading fee earned by
    token A, ensuring only effective positions are rewarded.
-   If price falls below a certain threshold, anyone can close the boosting program and insurance cab be claimed by liquidity providers.

### System Diagram

<img src='.imgs/system.png' width=400>
<br><br>

### Insurance

-   Protects only risk exposures on health assets.
-   Uses TWAP to prevent flash loan attacks.

<img src='.imgs/insurance.png' width=400>
<br><br>

### Using UniBoost as a Liquidity Provider

-   Stake the position NFT into UniBoost corresponding to the
    pool.
-   Claim reward for the position NFT, with a minimum staking
    time required.
-   Trigger the liquidation process if the price meets set conditions.
-   Claim insurance share after project liquidation by interacting
    with the contract.

### Using UniBoost as an Incentivizer

-   enable boosting program for a pool.
-   Add more incentive to the project.
-   Claim remaining incentive and insurance after project
    completion.

### Deployed Contracts on Gnosis Chiado Testnet

| Contract                   | Address                                                                                                                             |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Core**                   |                                                                                                                                     |
| UniBoost                   | [0x498b3b98B913348e9b599DE1B4f04ea92e62383F](https://blockscout.chiadochain.net/address/0x498b3b98B913348e9b599DE1B4f04ea92e62383F) |
| UniswapV3Factory           | [0x3419E607B475e1D73793e8c6b762969F808f2Cc2](https://blockscout.chiadochain.net/address/0x3419E607B475e1D73793e8c6b762969F808f2Cc2) |
| SwapRouter                 | [0x04FDF3C67525AbFFa9D56fA972cA0aa79c1b0455](https://blockscout.chiadochain.net/address/0x04FDF3C67525AbFFa9D56fA972cA0aa79c1b0455) |
| NonfungiblePositionManager | [0xFc3d86E2F5cd3d82f488735E4D163AcE5Cfaa3e3](https://blockscout.chiadochain.net/address/0xFc3d86E2F5cd3d82f488735E4D163AcE5Cfaa3e3) |
| WBTC/RKT - 0.3%            | [0x5b98B0bBCBA43e8C63215BCBE5D98638eAe7cC8c](https://blockscout.chiadochain.net/address/0x5b98B0bBCBA43e8C63215BCBE5D98638eAe7cC8c) |
| WBTC/DEV -1%               | [0x78B05EA36bf73BB22f88230FEa4aE536417D7Ee1](https://blockscout.chiadochain.net/address/0x78B05EA36bf73BB22f88230FEa4aE536417D7Ee1) |
| USDC/RKT - 0.05%           | [0x493D28D4264F2c309DD3207352D93E4dd4977c43](https://blockscout.chiadochain.net/address/0x493D28D4264F2c309DD3207352D93E4dd4977c43) |
| USDT/DEV - 1%              | [0xc7ff84d83cA703c00b43E0f0c80736bAE2a92D7e](https://blockscout.chiadochain.net/address/0xc7ff84d83cA703c00b43E0f0c80736bAE2a92D7e) |
| DAI/RKT - 0.3%             | [0x1A973e7B9207153F3450A3aD85145294c345738d](https://blockscout.chiadochain.net/address/0x1A973e7B9207153F3450A3aD85145294c345738d) |
| **Healthy Asset** _**H**_  |                                                                                                                                     |
| WETH                       | [0x4D9859097eac09DfB80624a8f47F3f24382CEf49](https://blockscout.chiadochain.net/address/0x4D9859097eac09DfB80624a8f47F3f24382CEf49) |
| WBTC                       | [0xb9c0e8a3E52042aa8e47055831318D9346153d7B](https://blockscout.chiadochain.net/address/0xb9c0e8a3E52042aa8e47055831318D9346153d7B) |
| USDC                       | [0x5d47c12d50BF02D62A5f9B3f57D6882e517514CC](https://blockscout.chiadochain.net/address/0x5d47c12d50BF02D62A5f9B3f57D6882e517514CC) |
| USDT                       | [0x7F1500AD7531544262edA72c8Bae7471723d5c24](https://blockscout.chiadochain.net/address/0x7F1500AD7531544262edA72c8Bae7471723d5c24) |
| DAI                        | [0x2C149B0a04b6018982221f2063Eea1838a3dD0a6](https://blockscout.chiadochain.net/address/0x2C149B0a04b6018982221f2063Eea1838a3dD0a6) |
| **Token** _**A**_          |                                                                                                                                     |
| RKT                        | [0xd5c3b7B3fC63c05593ce7DB91d6C4dE776a208eB](https://blockscout.chiadochain.net/address/0xd5c3b7B3fC63c05593ce7DB91d6C4dE776a208eB) |
| DEV                        | [0xC3D63C0584Cddf95c47c4fb8654Da6D11060CEBc](https://blockscout.chiadochain.net/address/0xC3D63C0584Cddf95c47c4fb8654Da6D11060CEBc) |
