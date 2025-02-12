// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { T1Owner } from "../../src/misc/T1Owner.sol";

// solhint-disable var-name-mixedcase

contract SwapERC20 is Script {
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private filler = vm.addr(ALICE_PRIVATE_KEY);

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        // Check if the market maker is set to this address
        if (IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).marketMaker() != filler) {
            IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).setMM(filler);
        }
        vm.stopBroadcast();
    }
}
