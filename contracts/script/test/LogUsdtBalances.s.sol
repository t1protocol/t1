// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L1WETHGateway } from "../../src/L1/gateways/L1WETHGateway.sol";
import { Script } from "forge-std/Script.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";
import { L1StandardERC20Gateway } from "../../src/L1/gateways/L1StandardERC20Gateway.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";

import { console } from "forge-std/console.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract LogUsdtBalances is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address payable L1_USDT_ADDR = payable(vm.envAddress("L1_USDT_ADDR"));
    address payable L2_USDT_ADDR = payable(vm.envAddress("L2_USDT_ADDR"));

    function run() external {
        address addr = vm.addr(L1_DEPLOYER_PRIVATE_KEY);

        vm.createSelectFork(vm.rpcUrl("sepolia"));
        console.log(
            "[%s] currently has [%18e] USDT on L1", vm.toString(addr), T1StandardERC20(L1_USDT_ADDR).balanceOf(addr)
        );

        if (L2_USDT_ADDR != address(0)) {
            vm.createSelectFork(vm.rpcUrl("t1"));
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
