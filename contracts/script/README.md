# README

There is a particular order the deployment scripts need to be ran in. There are multiple reasons for this:

- Upgradeable ProxyAdmin needs to be correct
- Contract Owners need to be correct
- Some L1 and L2 contracts (such as ETHGateways) need to have their target chain counterparts correctly configured

Should you deploy in an incorrect order, some of the functionalities might not work correctly even if your scripts ran
with no errors!

The magical deploy order is as follows:

- DeployL1BridgeProxyPlaceholder.s.sol
- DeployL1T1Owner.s.sol
- DeployL2BridgeProxyPlaceholder.s.sol
- DeployL2T1Owner.s.sol
- DeployL2BridgeContracts.s.sol
- DeployL1BridgeContracts.s.sol
- InitializeL1BridgeContracts.s.sol
- InitializeL2BridgeContracts.s.sol
- InitializeL1T1Owner.s.sol
- InitializeL2T1Owner.s.sol
