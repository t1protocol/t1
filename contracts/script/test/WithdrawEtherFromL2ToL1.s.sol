// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { IL2GatewayRouter } from "../../src/L2/gateways/IL2GatewayRouter.sol";

// solhint-disable var-name-mixedcase

contract WithdrawEtherFromL2ToL1 is Script {
    uint256 private TEST_PRIVATE_KEY = vm.envUint("TEST_PRIVATE_KEY");
    address private L2_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L2_GATEWAY_ROUTER_PROXY_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        vm.startBroadcast(TEST_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        IL2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).withdrawETH{ value: 0.001 ether }(0.001 ether, gasLimit);

        vm.stopBroadcast();
    }
}
