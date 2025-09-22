// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { xYieldVault } from "../../../../src/xYield/xYieldVault.sol";

contract RemoteWithdrawalFromXYieldArbitrum is Script {
    uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address underlyingToken = vm.envAddress("BASE_USDC_ADDR");
    address baseXYieldVaultAddress = vm.envAddress("BASE_XYIELD_VAULT_ADDR");
    address arbXYieldVaultAddress = vm.envAddress("ARB_XYIELD_VAULT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast(deployerPk);
        address deployer = vm.addr(deployerPk);
        xYieldVault xYield = xYieldVault(baseXYieldVaultAddress);

        uint32 targetChain = 42161; // Arbitrum CHAIN ID
        uint256 amountIn = 1e5;
        uint256 amountOut = 8e4;
        uint32 acrossApiQuoteTimestamp = uint32(block.timestamp - 300);
        uint32 fillDeadline = uint32(block.timestamp + 600);
        address exclusiveRelayer = address(0);
        uint32 exclusivityParameter = 0;

        uint256 depositAmount = 1e6; // 1 USDC
        IERC20(underlyingToken).approve(address(xYield), amountIn);
        xYield.depositTo(amountIn, deployer, targetChain, amountOut, exclusiveRelayer, acrossApiQuoteTimestamp, fillDeadline, exclusivityParameter);

        vm.stopBroadcast();
    }
}
