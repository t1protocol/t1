// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { xYieldVault } from "../../src/xYield/xYieldVault.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployBasexYieldVault is DeploymentUtils {
    function deploy() external {
        vm.createSelectFork(vm.rpcUrl("base"));
        logStart("DeployxYieldVault to Base");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address underlyingToken = vm.envAddress("BASE_UNDERLYING_TOKEN_ADDR");
        address guardian = vm.envAddress("BASE_XYIELD_GUARDIAN_ADDR");
        address yieldProtocol = vm.envAddress("BASE_YIELD_PROTOCOL_ADDR");
        string memory name = vm.envString("BASE_XYIELD_VAULT_NAME");
        string memory symbol = vm.envString("BASE_XYIELD_VAULT_SYMBOL");
        address settler = vm.envAddress("BASE_SETTLER_ADDR");

        vm.startBroadcast(deployerPk);

        xYieldVault vault = new xYieldVault(IERC20(underlyingToken), guardian, name, symbol, yieldProtocol, settler);

        vm.stopBroadcast();

        logAddress("BASE_XYIELD_VAULT_ADDR", address(vault));
        logEnd("DeployxYieldVault to Base");
    }
}
