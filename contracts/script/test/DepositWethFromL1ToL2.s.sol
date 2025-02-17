// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

// solhint-disable var-name-mixedcase

contract DepositWethFromL1ToL2 is Script {
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address payable private L1_WETH_ADDR = payable(vm.envAddress("L1_WETH_ADDR"));

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(ALICE_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        WrappedEther(L1_WETH_ADDR).approve(L1_GATEWAY_ROUTER_PROXY_ADDR, 0.01 ether);

        IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositERC20(L1_WETH_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
