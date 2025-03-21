// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";

// solhint-disable var-name-mixedcase

contract DepositUsdtFromL1ToL2 is Script {
    uint256 private TEST_PRIVATE_KEY = vm.envUint("TEST_PRIVATE_KEY");
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_USDT_ADDR = vm.envAddress("L1_USDT_ADDR");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(TEST_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        T1StandardERC20(L1_USDT_ADDR).approve(L1_GATEWAY_ROUTER_PROXY_ADDR, 1000 ether);

        IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositERC20(L1_USDT_ADDR, 1000 ether, gasLimit);

        address l2usdtAddress = IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).getL2ERC20Address(L1_USDT_ADDR);
        logAddress("L2_USDT_ADDR", l2usdtAddress);

        vm.stopBroadcast();
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
