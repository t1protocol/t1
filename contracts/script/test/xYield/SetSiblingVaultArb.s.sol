// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { xYieldVault } from "../../../src/xYield/xYieldVault.sol";

contract SetSiblingVaultArb is Script {
  uint256 ownerPk = vm.envUint("OWNER_PRIVATE_KEY");
  address xYieldVaultAddress = vm.envAddress("ARB_XYIELD_VAULT_ADDR");

  function run() external {
    vm.createSelectFork(vm.rpcUrl("arbitrum"));
    vm.startBroadcast(ownerPk);
    address owner = vm.addr(ownerPk);
    xYieldVault xYield = xYieldVault(xYieldVaultAddress);

    uint64 chainId = 8453; // BASE CHAIN ID
    address baseVault = vm.envAddress("BASE_XYIELD_VAULT_ADDR");
    address baseUnderlyingToken = vm.envAddress("BASE_UNDERLYING_TOKEN_ADDR");

    xYield.setSiblingVault(
        chainId,
        baseVault,
        baseUnderlyingToken
    );

    vm.stopBroadcast();
  }
}
