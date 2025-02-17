// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { IL2GatewayRouter } from "../../src/L2/gateways/IL2GatewayRouter.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";

// solhint-disable var-name-mixedcase

contract DepositWethFromL1ToL2 is Script {
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private L2_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L2_GATEWAY_ROUTER_PROXY_ADDR");
    address private L2_USDT_ADDR = vm.envAddress("L2_USDT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        vm.startBroadcast(ALICE_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        T1StandardERC20(L2_USDT_ADDR).approve(L2_GATEWAY_ROUTER_PROXY_ADDR, 0.01 ether);

        IL2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).withdrawERC20(L2_USDT_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
