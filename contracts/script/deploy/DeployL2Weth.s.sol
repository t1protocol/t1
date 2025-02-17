// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

// solhint-disable var-name-mixedcase

contract DeployL2Weth is Script, DeploymentUtils {
    function run() external {
        logStart("DeployL2Weth");

        uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);
        WrappedEther weth = new WrappedEther();
        weth.deposit{ value: 100 ether }();
        vm.stopBroadcast();

        logAddress("L2_WETH_ADDR", address(weth));

        logEnd("DeployL2Weth");
    }
}
