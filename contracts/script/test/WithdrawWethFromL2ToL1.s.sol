// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { IL2GatewayRouter } from "../../src/L2/gateways/IL2GatewayRouter.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

// solhint-disable var-name-mixedcase

contract DepositWethFromL2ToL2 is Script {
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private L2_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L2_GATEWAY_ROUTER_PROXY_ADDR");
    address payable private L2_WETH_ADDR = payable(vm.envAddress("L2_WETH_ADDR"));

    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        vm.startBroadcast(ALICE_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        WrappedEther(L2_WETH_ADDR).approve(L2_GATEWAY_ROUTER_PROXY_ADDR, 0.01 ether);

        IL2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).withdrawERC20(L2_WETH_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
