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
11. [InitializeL2T1Owner.s.sol](./deploy/nitializeL2T1Owner.s.sol)

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
  - [Swap ERC20s against bridge reserves](./test/swapERC20.s.sol)
- Chore
  - [Check L1 and L2 USDT balances](./test/LogUsdtBalances.s.sol)
