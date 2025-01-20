// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Script } from "forge-std/Script.sol";
import { L1ETHGateway } from "../src/L1/gateways/L1ETHGateway.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract TriggerL1CanonicalBridge is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");

    function run() external {
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        L1ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).depositETH{ value: 0.001ether }(
            0.001ether, gasLimit
        );

        vm.stopBroadcast();
    }
}
