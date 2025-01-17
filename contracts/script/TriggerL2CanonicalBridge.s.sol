// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Script } from "forge-std/Script.sol";
import { L2ETHGateway } from "../src/L2/gateways/L2ETHGateway.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract TriggerL2CanonicalBridge is Script {
    uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address L2_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ETH_GATEWAY_PROXY_ADDR");

    function run() external {
        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        uint256 ZERO_POINT_ZERO_ZERO_ONE_ETHER = 1_000_000_000_000_000;
        uint256 gasLimit = 1_000_000;

        L2ETHGateway(L2_ETH_GATEWAY_PROXY_ADDR).withdrawETH{ value: ZERO_POINT_ZERO_ZERO_ONE_ETHER }(
            ZERO_POINT_ZERO_ZERO_ONE_ETHER, gasLimit
        );

        vm.stopBroadcast();
    }
}
