// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L1WETHGateway } from "../src/L1/gateways/L1WETHGateway.sol";
import { Script } from "forge-std/Script.sol";
import { WrappedEther } from "../src/L2/predeploys/WrappedEther.sol";
import { T1StandardERC20 } from "../src/libraries/token/T1StandardERC20.sol";
import { L2StandardERC20Gateway } from "../src/L2/gateways/L2StandardERC20Gateway.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DepositWethFromL1ToL2 is Script {
    uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address payable L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR =
        payable(vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR"));

    address payable L2_USDT_ADDR = payable(vm.envAddress("L2_USDT_ADDR"));

    function run() external {
        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        T1StandardERC20(L2_USDT_ADDR).approve(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR, 0.01 ether);

        L2StandardERC20Gateway(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).withdrawERC20(L2_USDT_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
