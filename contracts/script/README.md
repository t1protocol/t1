# README

## Deploy

You can use `./deploy.sh` in the `contracts` folder to automatically deploy all the contracts. Make sure to have the
`.env` file clean from any previous deployments.

There is a particular order the deployment scripts need to be run in. There are multiple reasons for this:

- Upgradeable ProxyAdmin needs to be correct
- Contract Owners need to be correct
- Some L1 and L2 contracts (such as ETHGateways) need to have their target chain counterparts correctly configured

Should you deploy in an incorrect order, some of the functionalities might not work correctly even if your scripts run
with no errors!

The magical deploy order is as follows:

1. [DeployL1BridgeProxyPlaceholder.s.sol](./deploy/DeployL1BridgeProxyPlaceholder.s.sol)
2. [DeployL1T1Owner.s.sol](./deploy/DeployL1T1Owner.s.sol)
3. [DeployL2BridgeProxyPlaceholder.s.sol](./deploy/DeployL2BridgeProxyPlaceholder.s.sol)
4. [DeployL2T1Owner.s.sol](./deploy/DeployL2T1Owner.s.sol)
5. [DeployL2Weth.s.sol](./deploy/DeployL2Weth.s.sol)
6. [DeployL2BridgeContracts.s.sol](./deploy/DeployL2BridgeContracts.s.sol)
7. [DeployL1BridgeContracts.s.sol](./deploy/DeployL1BridgeContracts.s.sol)
8. [InitializeL1BridgeContracts.s.sol](./deploy/InitializeL1BridgeContracts.s.sol)
9. [InitializeL2BridgeContracts.s.sol](./deploy/InitializeL2BridgeContracts.s.sol)
10. [InitializeL1T1Owner.s.sol](./deploy/InitializeL1T1Owner.s.sol)
11. [InitializeL2T1Owner.s.sol](./deploy/InitializeL2T1Owner.s.sol)
12. [FirstUsdtDepositFromL1ToL2.s.sol](./configure/FirstUsdtDepositFromL1ToL2.s.sol)
13. [SetMM.s.sol](./configure/SetMM.s.sol)
14. [AllowRouterToTransfer.s.sol](./configure/AllowRouterToTransfer.s.sol)
15. [DeployL1T1XChainReader.s.sol](./deploy/DeployL1T1XChainReader.s.sol)
16. [DeployL2T1XChainReader.s.sol](./deploy/DeployL2T1XChainReader.s.sol)
17. [DeployT1ERC7683.s.sol](./deploy/7683/DeployT1ERC7683.s.sol)

## Deploy 7683 Contract

To deploy the 7683 contract, follow these steps:

### Deploy L1_7683

First, deploy the L1 router by running the following command:

```bash
forge script ./script/deploy/7683/DeployT1ERC7683.s.sol:DeployT1ERC7683 --sig "deploy_7683()" --rpc-url $T1_L1_RPC --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.etherscan.io/api
```

### Deploy L2_7683

Next, deploy the L2 router with the following command:

```bash
forge script ./script/deploy/7683/DeployT1ERC7683.s.sol:DeployT1ERC7683 --sig "deploy_7683()" --rpc-url $T1_L2_RPC --broadcast --verify --verifier blockscout --verifier-url https://explorer.devnet.t1protocol.com/api
```

### Initialize Functions

After deploying the routers, you will need to initialize them by running the following commands:

Initialize L1_7683:

```bash
forge script ./script/deploy/7683/DeployT1ERC7683.s.sol:DeployT1ERC7683 --sig "initialize_7683()" --rpc-url $T1_L1_RPC --broadcast
```

Initialize L2_7683:

```bash
forge script ./script/deploy/7683/DeployT1ERC7683.s.sol:DeployT1ERC7683 --sig "initialize_7683()" --rpc-url $T1_L2_RPC --broadcast
```

## Configure

Scripts to configure the canonical bridge functionalities:

- Configure
  - [First USDT deposit from L1 to L2](./configure/FirstUsdtDepositFromL1ToL2.s.sol)
  - [Allow router to transfer](./configure/AllowRouterToTransfer.s.sol)
  - [Set market maker](./configure/SetMM.s.sol)

## Test

Scripts to test the canonical bridge functionalities:

- Deposits
  - [Deposit Ether from L1->L2](./test/DepositEtherFromL1ToL2.s.sol)
  - [Deposit WETH from L1->L2](./test/DepositWethFromL1ToL2.s.sol)
  - [Deposit USDT from L1->L2](./test/DepositUsdtFromL1ToL2.s.sol)
- Withdrawals
  - [Withdraw Ether from L2->L1](./test/WithdrawEtherFromL2ToL1.s.sol)
  - [Withdraw WETH from L2->L1](./test/WithdrawWethFromL2ToL1.s.sol)
  - [Withdraw USDT from L2->L1](./test/WithdrawUsdtFromL2ToL1.s.sol)
- Swaps
  - [Swap ERC20s against bridge reserves](./test/SwapERC20.s.sol)
- Utility
  - [Log all balances from L1 & L2](./test/LogBalances.s.sol)

Miscellaneous Scripts:

- 7683
  - [Create an intent on L1, fill it on L2, and settle it from L2](./test/7683/T1ERC7683L1ToL2.s.sol)
  - [Create an intent on L1, fill it on L2, and settle it from L1](./test/7683/T1ERC7683L1ToL2.s.sol)
  - [Create an intent on L2, fill it on L1, and settle it from L2](./test/7683/T1ERC7683L2ToL1.s.sol)
  - [Create an intent on Arb, fill it on Base, and settle it from Arb](./test/7683/T1ERC7683ArbToBase.s.sol)
  - [Create an intent on Base, fill it on Arb, and settle it from Base](./test/7683/T1ERC7683BaseToArb.s.sol)

## 🔄 Upgrade

Scripts to upgrade contract implementations:

- [T1Chain implementation](./upgrade/UpgradeT1Chain.s.sol)

  ```bash
  forge script ./script/upgrade/UpgradeT1Chain.s.sol:UpgradeT1Chain --rpc-url $T1_L1_RPC --broadcast
  ```

- [T1XChainReader implementation](./upgrade/UpgradeT1XChainReader.s.sol) - Upgrade on Sepolia (production)

  ```bash
  forge script ./script/upgrade/UpgradeT1XChainReader.s.sol:UpgradeT1XChainReader --rpc-url $T1_L1_RPC --broadcast
  ```

- [T1XChainReader implementation (Local)](./upgrade/UpgradeT1XChainReaderLocal.s.sol) - Upgrade on local network
  ```bash
  forge script ./script/upgrade/UpgradeT1XChainReaderLocal.s.sol:UpgradeT1XChainReaderLocal --rpc-url localhost --broadcast
  ```

## Deploying 7683 to Arbitrum Sepolia and Base Sepolia

This section walks you through deploying the 7683 system to both Arbitrum Sepolia and Base Sepolia testnets. Since reads
use event logs only, no dedicated messenger contracts are required. You will deploy just the xChainReader and the
ERC-7683 pull modules. Each Forge script broadcasts the tx, verifies it on the relevant explorer API, and uses your API
key to confirm source code.

### Deploy a new Proxy Admin

Deploys a proxy admin to each chain which is responsible for holding admin funtions on xChainReaders, so that we can
transfer responsibiltiy to n chains without tedium

#### Arbitrum Proxy Admin

```bash
forge script ./deploy/DeployArbT1ProxyAdmin.s.sol:DeployArbT1ProxyAdmin --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.arbiscan.io/api --etherscan-api-key $ARBISCAN_API_KEY
```

#### Base Proxy Admin

```bash
forge script ./deploy/DeployBaseT1ProxyAdmin.s.sol:DeployBaseT1ProxyAdmin --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.basescan.org/api --etherscan-api-key $BASESCAN_API_KEY
```

### Deploying xChainRead

Deploys the xChainReader contract, which packages cross-chain read requests and handles callbacks to the requesting
contracts.

#### Arbitrum Sepolia XChain Reader

```bash
forge script ./deploy/DeployArbT1XChainReader.s.sol:DeployArbT1XChainReader --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.arbiscan.io/api --etherscan-api-key $ARBISCAN_API_KEY
```

#### Base Sepolia XChain Reader

```bash
forge script ./deploy/DeployBaseT1XChainReader.s.sol:DeployBaseT1XChainReader --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.basescan.org/api --etherscan-api-key $BASESCAN_API_KEY
```

### Deploying 7683

Deploys ERC-7683 contracts to the target chain, verifies and initializes them.

#### Arbitrum Sepolia 7683 Module Deployment

```bash
forge script ./deploy/7683/DeployArbT1ERC7683.s.sol:DeployArbT1ERC7683 --sig "deploy()"  --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.arbiscan.io/api --etherscan-api-key $ARBISCAN_API_KEY
```

#### Base Sepolia 7683 Module Deployment

```bash
forge script ./deploy/7683/DeployBaseT1ERC7683.s.sol:DeployBaseT1ERC7683 --sig "deploy()" --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.basescan.org/api --etherscan-api-key $BASESCAN_API_KEY
```

#### Arbitrum Sepolia 7683 Module Init

```bash
forge script ./deploy/7683/DeployArbT1ERC7683.s.sol:DeployArbT1ERC7683 --sig "init()" --broadcast
```

#### Base Sepolia 7683 Module Init

```bash
forge script ./deploy/7683/DeployBaseT1ERC7683.s.sol:DeployBaseT1ERC7683 --sig "init()" --broadcast
```

## Testing 7683 on Arbitrum Sepolia and Base Sepolia

### Testing 7683 on Arbitrum Sepolia

1. Open an intent on Arbitrum Sepolia.

```bash
forge script ./test/7683/T1ERC7683ArbToBase.s.sol:AliceSetupScript --rpc-url $T1_L1_RPC --broadcast
```

2. If a solver does not immediately fill the intent, you can fill it on Base Sepolia.

```bash
forge script ./test/7683/T1ERC7683ArbToBase.s.sol:SolverFillScript --rpc-url $T1_L2_RPC --broadcast
```

3. If you filled your own intent, you must also settle it by calling `verifySettlement` on Arbitrum Sepolia.

```bash
forge script ./test/7683/T1ERC7683ArbToBase.s.sol:SettlementScript --rpc-url $T1_L1_RPC --broadcast
```

### Testing 7683 on Base Sepolia

1. Open an intent on Base Sepolia.

```bash
forge script ./test/7683/T1ERC7683BaseToArb.s.sol:AliceSetupScript --rpc-url $T1_L1_RPC --broadcast
```

2. If a solver does not immediately fill the intent, you can fill it on Arbitrum Sepolia.

```bash
forge script ./test/7683/T1ERC7683BaseToArb.s.sol:SolverFillScript --rpc-url $T1_L2_RPC --broadcast
```

3. If you filled your own intent, you must also settle it by calling `verifySettlement` on Base Sepolia.

```bash
forge script ./test/7683/T1ERC7683BaseToArb.s.sol:SettlementScript --rpc-url $T1_L1_RPC --broadcast
```
