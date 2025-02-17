// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";

// solhint-disable var-name-mixedcase

contract LogBalances is Script {

    address private L1_USDT_ADDR = vm.envAddress("L1_USDT_ADDR");
    address private L2_USDT_ADDR = vm.envOr("L2_USDT_ADDR", address(0));

    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");
    address private L2_WETH_ADDR = vm.envAddress("L2_WETH_ADDR");

    function run(address addr) external {

        vm.createSelectFork(vm.rpcUrl("sepolia"));
        console.log(
            "[%s] currently has [%18e] ETH on L1", vm.toString(addr), addr.balance
        );
        console.log(
            "[%s] currently has [%18e] WETH on L1", vm.toString(addr), T1StandardERC20(L1_WETH_ADDR).balanceOf(addr)
        );
        console.log(
            "[%s] currently has [%18e] USDT on L1", vm.toString(addr), T1StandardERC20(L1_USDT_ADDR).balanceOf(addr)
        );

        vm.createSelectFork(vm.rpcUrl("t1"));
        console.log(
            "[%s] currently has [%18e] ETH on L2", vm.toString(addr), addr.balance
        );
        console.log(
            "[%s] currently has [%18e] WETH on L2", vm.toString(addr), T1StandardERC20(L2_WETH_ADDR).balanceOf(addr)
        );
        if (L2_USDT_ADDR != address(0)) {
            console.log(
                "[%s] currently has [%18e] USDT on L2", vm.toString(addr), T1StandardERC20(L2_USDT_ADDR).balanceOf(addr)
            );
        } else {
            console.log(
                "L2_USDT_ADDR was not configured! this might mean that [%s] currently has 0 USDT on L2",
                vm.toString(addr)
            );
        }
    }
}
