// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { MintableERC20 } from "../../../src/xYield/MintableERC20.sol";
import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

contract DeployMintableERC20 is DeploymentUtils {
    MintableERC20 private token;

    function deploy() external {
        selectMainnetOrSepoliaFork("base");
        startBroadcastWithDeployerKeyIfItExists();

        token = new MintableERC20(address(0x6c8E1d54297aAe7C34f1F5cF73559e621a394eFb), "xyUSDC", "xyUSDC");

        vm.stopBroadcast();
    }
}
