// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";
import { xYieldVault } from "../../../src/xYield/xYieldVault.sol";

contract SetArbitrumSiblingVaultOnBasexYieldVault is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("base"));
        logStart("set Arbitrum sibling vault on Base xYieldVault");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdcArbitrum = vm.envAddress("ARB_USDC_ADDR");
        address xYieldBaseAddr = vm.envAddress("BASE_XYIELD_VAULT_ADDR");
        address xYieldArbitrum = vm.envAddress("ARB_XYIELD_VAULT_ADDR");
        address multicallHandlerArbitrum = vm.envAddress("ARB_ACROSS_MULTICALL_HANDLER_ADDR");
        uint64 arbitrumChainId = 42161;

        vm.startBroadcast(deployerPk);

        xYieldVault xYieldBase = xYieldVault(xYieldBaseAddr);

        xYieldBase.setSiblingVault(
            arbitrumChainId, address(xYieldArbitrum), address(usdcArbitrum), multicallHandlerArbitrum
        );

        vm.stopBroadcast();

        logEnd("set Arbitrum sibling vault on Base xYieldVault");
    }
}
