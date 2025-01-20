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
5. [DeployL2BridgeContracts.s.sol](DeployL2BridgeContracts.s.sol)
6. [DeployL1BridgeContracts.s.sol](DeployL1BridgeContracts.s.sol)
7. [InitializeL1BridgeContracts.s.sol](InitializeL1BridgeContracts.s.sol)
8. [InitializeL2BridgeContracts.s.sol](InitializeL2BridgeContracts.s.sol)
9. [InitializeL1T1Owner.s.sol](InitializeL1T1Owner.s.sol)
10. [InitializeL2T1Owner.s.sol](InitializeL2T1Owner.s.sol)
