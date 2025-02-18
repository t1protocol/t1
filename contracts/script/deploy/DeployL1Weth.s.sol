// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

// solhint-disable var-name-mixedcase

contract DeployL1Weth is Script, DeploymentUtils {
    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");

    function run() external {
        logStart("DeployL1Weth");

        // deploy weth only if we're running a private L1 network
        if (L1_WETH_ADDR == address(0)) {
            uint256 L1_WETH_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_WETH_DEPLOYER_PRIVATE_KEY");
            vm.startBroadcast(L1_WETH_DEPLOYER_PRIVATE_KEY);
            WrappedEther weth = new WrappedEther();
            L1_WETH_ADDR = address(weth);
            vm.stopBroadcast();
        }

        logAddress("L1_WETH_ADDR", L1_WETH_ADDR);

        logEnd("DeployL1Weth");
    }
}
