# README

## Deploy

You can use `./deploy.sh` in the `contracts` folder to automatically deploy all the contracts. Make sure to have the
`.env` file clean from any previous deployments.

There is a particular order the deployment scripts need to be ran in. There are multiple reasons for this:

- Upgradeable ProxyAdmin needs to be correct
- Contract Owners need to be correct
- Some L1 and L2 contracts (such as ETHGateways) need to have their target chain counterparts correctly configured

Should you deploy in an incorrect order, some of the functionalities might not work correctly even if your scripts ran
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

## Deploy 7683 Contract

To deploy the 7683 contract, follow these steps:

### Deploy L1 Router

First, deploy the L1 router by running the following command:

```bash
forge script ./script/deploy/DeployRouterERC7683.s.sol:RouterDeployScript --sig "deployL1Router()" --rpc-url $T1_L1_RPC --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.etherscan.io/api --etherscan-api-key XXXXXX
```

### Deploy L2 Router

Next, deploy the L2 router with the following command:

```bash
forge script ./script/deploy/DeployRouterERC7683.s.sol:RouterDeployScript --sig "deployL2Router()" --rpc-url $T1_L2_RPC --broadcast --verify --verifier blockscout --verifier-url https://explorer.devnet.t1protocol.com/api
```

### Initialize Functions

After deploying the routers, you will need to initialize them by running the following commands:

Initialize L1 Router:

```bash
forge script ./script/deploy/DeployRouterERC7683.s.sol:RouterDeployScript --sig "initializeL1Router()" --rpc-url $T1_L1_RPC --broadcast
```

Initialize L2 Router:

```bash
forge script ./script/deploy/DeployRouterERC7683.s.sol:RouterDeployScript --sig "initializeL2Router()" --rpc-url $T1_L2_RPC --broadcast
```

## Test

Scripts to test the canonical bridge functionalities:

- Deposits
  - [Deposit Ether from L1->L2](./test/DepositEtherFromL1ToL2.s.sol)
  - [Deposit WETH from L1->L2](./test/DepositWethFromL1ToL2.s.sol)
  - [Deposit USDT from L1->L2](./test/DepositUsdtFromL1ToL2.s.sol)
- Witdrawals
  - [Withdraw Ether from L2->L1](./test/WithdrawEtherFromL2ToL1.s.sol)
  - [Withdraw WETH from L2->L1](./test/WithdrawWethFromL2ToL1.s.sol)
  - [Withdraw USDT from L2->L1](./test/WithdrawUsdtFromL2ToL1.s.sol)
- Swaps
  - [Swap ERC20s against bridge reserves](./test/SwapERC20.s.sol)
  - [Allow router to transfer](./test/AllowRouterToTransfer.s.sol)
  - [Set market maker](./test/SetMM.s.sol)
- Chore
  - [Check Alice balances on L1/L2](./test/LogBalances.s.sol)
- 7683
  - [Create an intent to on L1 and fill it on L2](./test/7683E2E.s.sol)