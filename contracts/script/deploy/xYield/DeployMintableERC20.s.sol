// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { MintableERC20 } from "../../../src/xYield/MintableERC20.sol";
import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

contract DeployMintableERC20 is DeploymentUtils {
    MintableERC20 private token;

    function deploy() external {
        selectMainnetOrSepoliaFork("arbitrum");
        startBroadcastWithDeployerKeyIfItExists();

        token = new MintableERC20(address(0x8764BD4c58cc71bEe12C36deA228fd22a1B2723C), "xyUSDC", "xyUSDC");

        vm.stopBroadcast();
    }
}
