// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { T1Owner } from "../../src/misc/T1Owner.sol";

// solhint-disable var-name-mixedcase

contract SetMM is Script {
    bytes32 private constant SECURITY_COUNCIL_NO_DELAY_ROLE = keccak256("SECURITY_COUNCIL_NO_DELAY_ROLE");

    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_T1_OWNER_ADDR = vm.envAddress("L1_T1_OWNER_ADDR");
    uint256 private L1_SECURITY_COUNCIL_PRIVATE_KEY = vm.envUint("L1_SECURITY_COUNCIL_PRIVATE_KEY");
    address private newMarketMaker = vm.envAddress("MARKET_MAKER_ADDRESS");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(L1_SECURITY_COUNCIL_PRIVATE_KEY);

        // Check if the market maker is set to this address
        if (IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).marketMaker() != newMarketMaker) {
            T1Owner(payable(L1_T1_OWNER_ADDR)).execute(
                L1_GATEWAY_ROUTER_PROXY_ADDR,
                0,
                abi.encodeWithSelector(IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).setMM.selector, newMarketMaker),
                SECURITY_COUNCIL_NO_DELAY_ROLE
            );
        }

        console.log("[%s] is the new market maker", IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).marketMaker());
        vm.stopBroadcast();
    }
}
