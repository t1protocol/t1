// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L1WETHGateway } from "../src/L1/gateways/L1WETHGateway.sol";
import { L1ETHGateway } from "../src/L1/gateways/L1ETHGateway.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Script } from "forge-std/Script.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DepositWethFromL1ToL2 is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");

    address L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");

    function run() external {
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        L1WETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).depositERC20(L1_WETH_ADDR, 1 ether, gasLimit);

        vm.stopBroadcast();
    }
}
