// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L1WETHGateway } from "../../src/L1/gateways/L1WETHGateway.sol";
import { Script } from "forge-std/Script.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { IL2ERC20Gateway } from "../../src/L2/gateways/IL2ERC20Gateway.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DepositWethFromL1ToL2 is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR =
        vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR");

    address payable L2_USDT_ADDR = payable(vm.envAddress("L2_USDT_ADDR"));

    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        T1StandardERC20(L2_USDT_ADDR).approve(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR, 0.01 ether);

        IL2ERC20Gateway(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).withdrawERC20(L2_USDT_ADDR, 0.01 ether, gasLimit);

        vm.stopBroadcast();
    }
}
