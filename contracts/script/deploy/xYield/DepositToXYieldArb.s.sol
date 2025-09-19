// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { xYieldVault } from "../../../../src/xYield/xYieldVault.sol";

contract DepositToXYieldArbitrum is Script {
    uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address underlyingToken = vm.envAddress("ARB_USDC_ADDR");
    address xYieldVaultAddress = vm.envAddress("ARB_XYIELD_VAULT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(deployerPk);
        address deployer = vm.addr(deployerPk);
        xYieldVault xYield = xYieldVault(xYieldVaultAddress);

        uint256 depositAmount = 1e6; // 1 USDC
        IERC20(underlyingToken).approve(address(xYield), depositAmount);
        uint256 aliceShares = xYield.deposit(depositAmount, deployer);

        vm.stopBroadcast();
    }
}
