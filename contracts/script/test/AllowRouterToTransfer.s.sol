// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { IL1StandardERC20Gateway } from "../../src/L1/gateways/IL1StandardERC20Gateway.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";

// solhint-disable var-name-mixedcase

contract AllowRouterToTransfer is Script {
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    uint256 private MARKET_MAKER_PRIVATE_KEY = vm.envUint("MARKET_MAKER_PRIVATE_KEY");

    // List of token addresses listed on tDEX
    address[] public ERC20s = [vm.envAddress("L1_WETH_ADDR"), vm.envAddress("L1_USDT_ADDR")];

    address private marketMaker = vm.addr(MARKET_MAKER_PRIVATE_KEY);

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(MARKET_MAKER_PRIVATE_KEY);

        address permit2 = IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).permit2();

        // Check allowance for ERC20s
        for (uint256 i = 0; i < ERC20s.length - 1; i++) {
            if (
                T1StandardERC20(ERC20s[i]).allowance(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, permit2)
                    < type(uint160).max / 2
            ) {
                IL1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).allowRouterToTransfer(
                    ERC20s[i], type(uint160).max, uint48(block.timestamp + 10_000_000)
                );
            }
        }

        vm.stopBroadcast();
    }
}
