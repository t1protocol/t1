// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { xYieldVault } from "../../src/xYield/xYieldVault.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployArbxYieldVault is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        logStart("DeployxYieldVault to Arbitrum");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address underlyingToken = vm.envAddress("ARB_USDC_ADDR");
        address guardian = vm.envAddress("XYIELD_GUARDIAN_ADDR");
        address yieldProtocol = vm.envAddress("ARB_YIELD_PROTOCOL_ADDR");
        string memory name = vm.envString("ARB_XYIELD_VAULT_NAME");
        string memory symbol = vm.envString("ARB_XYIELD_VAULT_SYMBOL");
        address settler = vm.envAddress("ARB_SETTLER_ADDR");

        vm.startBroadcast(deployerPk);

        xYieldVault vault = new xYieldVault(IERC20(underlyingToken), guardian, name, symbol, yieldProtocol, settler);

        vm.stopBroadcast();

        logAddress("ARB_XYIELD_VAULT_ADDR", address(vault));
        logEnd("DeployxYieldVault to Arbitrum");
    }
}
