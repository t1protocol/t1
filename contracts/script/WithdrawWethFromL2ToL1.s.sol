// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L2WETHGateway } from "../src/L2/gateways/L2WETHGateway.sol";
import { Script } from "forge-std/Script.sol";
import { WrappedEther } from "../src/L2/predeploys/WrappedEther.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DepositWethFromL2ToL2 is Script {
    uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address payable L2_WETH_GATEWAY_PROXY_ADDR = payable(vm.envAddress("L2_WETH_GATEWAY_PROXY_ADDR"));

    address payable L2_WETH_ADDR = payable(vm.envAddress("L2_WETH_ADDR"));

    function run() external {
        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        WrappedEther(L2_WETH_ADDR).approve(L2_WETH_GATEWAY_PROXY_ADDR, 0.01 ether);

        L2WETHGateway(L2_WETH_GATEWAY_PROXY_ADDR).withdrawERC20(L2_WETH_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
