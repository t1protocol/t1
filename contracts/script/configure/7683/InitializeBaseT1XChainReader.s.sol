// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";
import { T1XChainReader } from "../../../src/libraries/xChain/T1XChainReader.sol";

contract InitializeBaseT1XChainReader is DeploymentUtils {
    address internal proxy = vm.envAddress("BASE_T1_X_CHAIN_READ_PROXY_ADDR");
    address internal MANAGER_MULTISIG = vm.envAddress("MANAGER_MULTISIG_ADDR");

    function init() external {
        selectMainnetOrSepoliaFork("base");
        startBroadcastWithDeployerKeyIfItExists();

        T1XChainReader(address(proxy)).initialize(MANAGER_MULTISIG);

        vm.stopBroadcast();
    }
}