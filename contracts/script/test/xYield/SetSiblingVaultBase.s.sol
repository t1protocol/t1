// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { xYieldVault } from "../../../src/xYield/xYieldVault.sol";

contract SetSiblingVaultBase is Script {
    uint256 ownerPk = vm.envUint("OWNER_PRIVATE_KEY");
    address xYieldVaultAddress = vm.envAddress("BASE_XYIELD_VAULT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast(ownerPk);
        address owner = vm.addr(ownerPk);
        xYieldVault xYield = xYieldVault(xYieldVaultAddress);

        uint64 chainId = 42_161; // ARBITRUM CHAIN ID
        address arbVault = vm.envAddress("ARB_XYIELD_VAULT_ADDR");
        address arbUnderlyingToken = vm.envAddress("ARB_UNDERLYING_TOKEN_ADDR");

        xYield.setSiblingVault(chainId, arbVault, arbUnderlyingToken);

        vm.stopBroadcast();
    }
}
