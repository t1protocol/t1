// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { xYieldVault } from "../../../../src/xYield/xYieldVault.sol";

contract RebalanceXYieldFromArbitrumToBase is Script {
    uint256 guardianPk = vm.envUint("GUARDIAN_PRIVATE_KEY");
    address underlyingToken = vm.envAddress("ARB_USDC_ADDR");
    address xYieldVaultAddress = vm.envAddress("ARB_XYIELD_VAULT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(guardianPk);
        address guardian = vm.addr(guardianPk);
        xYieldVault xYield = xYieldVault(xYieldVaultAddress);

        uint256 rebalanceId = uint256(keccak256(abi.encodePacked(block.timestamp, block.chainid)));
        uint32 targetChain = 8453; // BASE CHAIN ID
        uint256 amountIn = 2e6;
        uint256 amountOut = 1e6;
        uint32 acrossApiQuoteTimestamp = uint32(block.timestamp - 100);

        xYield.rebalance(rebalanceId, targetChain, amountIn, amountOut, acrossApiQuoteTimestamp);

        vm.stopBroadcast();
    }
}
