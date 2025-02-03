# README

There is a particular order the deployment scripts need to be ran in. There are multiple reasons for this:

- Upgradeable ProxyAdmin needs to be correct
- Contract Owners need to be correct
- Some L1 and L2 contracts (such as ETHGateways) need to have their target chain counterparts correctly configured

Should you deploy in an incorrect order, some of the functionalities might not work correctly even if your scripts ran
with no errors!

The magical deploy order is as follows:

1. [DeployL1BridgeProxyPlaceholder.s.sol](DeployL1BridgeProxyPlaceholder.s.sol)
2. [DeployL1T1Owner.s.sol](DeployL1T1Owner.s.sol)
3. [DeployL2BridgeProxyPlaceholder.s.sol](DeployL2BridgeProxyPlaceholder.s.sol)
4. [DeployL2T1Owner.s.sol](DeployL2T1Owner.s.sol)
5. [DeployL2Weth.s.sol](DeployL2Weth.s.sol)
6. [DeployL2BridgeContracts.s.sol](DeployL2BridgeContracts.s.sol)
7. [DeployL1BridgeContracts.s.sol](DeployL1BridgeContracts.s.sol)
8. [InitializeL1BridgeContracts.s.sol](InitializeL1BridgeContracts.s.sol)
9. [InitializeL2BridgeContracts.s.sol](InitializeL2BridgeContracts.s.sol)
10. [InitializeL1T1Owner.s.sol](InitializeL1T1Owner.s.sol)
11. [InitializeL2T1Owner.s.sol](InitializeL2T1Owner.s.sol)

## Testing

Scripts to test the canonical bridge:

- ETH
  - [Deposit Ether from L1->L2](DepositEtherFromL1ToL2.s.sol)
  - [Withdraw Ether from L2->L1](WithdrawEtherFromL2ToL1.s.sol)
- WETH
  - [Deposit WETH from L1->L2](DepositWethFromL1ToL2.s.sol)
  - [Withdraw WETH from L2->L1](WithdrawWethFromL2ToL1.s.sol)
- USDT
  - [Deposit USDT from L1->L2](DepositUsdtFromL1ToL2.s.sol)
  - [Withdraw USDT from L2->L1](WithdrawUsdtFromL2ToL1.s.sol)
