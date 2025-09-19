// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";
import { xYieldVault } from "../../../src/xYield/xYieldVault.sol";

contract SetBaseSiblingVaultOnArbxYieldVault is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        logStart("set Base sibling vault on Arbitrum xYieldVault");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdcBase = vm.envAddress("BASE_USDC_ADDR");
        address xYieldArbitrumAddr = vm.envAddress("ARB_XYIELD_VAULT_ADDR");
        address xYieldBase = vm.envAddress("BASE_XYIELD_VAULT_ADDR");
        address multicallHandlerBase = vm.envAddress("BASE_ACROSS_MULTICALL_HANDLER_ADDR");
        uint64 baseChainId = 8453;

        vm.startBroadcast(deployerPk);

        xYieldVault xYieldArbitrum = xYieldVault(xYieldArbitrumAddr);

        xYieldArbitrum.setSiblingVault(
            baseChainId, address(xYieldBase), address(usdcBase), multicallHandlerBase
        );

        vm.stopBroadcast();

        logEnd("set Base sibling vault on Arbitrum xYieldVault");
    }
}
