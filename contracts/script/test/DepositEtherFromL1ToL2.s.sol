// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";

// solhint-disable var-name-mixedcase

contract DepositEtherFromL1ToL2 is Script {
    uint256 private TEST_PRIVATE_KEY = vm.envUint("TEST_PRIVATE_KEY");
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(TEST_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositETH{ value: 0.001 ether }(0.001 ether, gasLimit);

        vm.stopBroadcast();
    }
}
