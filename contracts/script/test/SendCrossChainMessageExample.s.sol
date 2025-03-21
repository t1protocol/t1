// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { CrossChainExample } from "../deploy/DeployCrossChainExample.s.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract SendCrossChainMessageExample is Script {
    function send_l1_to_l2_message() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));

        address l1ExampleAddr = vm.envAddress("L1_EXAMPLE_ADDR");
        address l2ExampleAddr = vm.envAddress("L2_EXAMPLE_ADDR");
        uint64 l2ChainId = T1Constants.T1_DEVNET_CHAIN_ID;
        uint256 userPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        uint256 gasLimit = 500_000;

        CrossChainExample l1Example = CrossChainExample(l1ExampleAddr);

        // prepare a call to the echo function
        bytes memory messageData = abi.encodeWithSelector(CrossChainExample.echo.selector, "Hello from L1");

        vm.startBroadcast(userPk);

        bytes32 requestId =
            l1Example.sendCrossChainRequest{ value: gasLimit }(l2ChainId, l2ExampleAddr, gasLimit, messageData);

        console2.log("sent message from l1->l2 with requestId:", vm.toString(requestId));

        vm.stopBroadcast();
    }

    function send_l2_to_l1_message() public {
        vm.createSelectFork(vm.rpcUrl("t1"));

        address l1ExampleAddr = vm.envAddress("L1_EXAMPLE_ADDR");
        address l2ExampleAddr = vm.envAddress("L2_EXAMPLE_ADDR");
        uint256 userPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        uint64 l1ChainId = T1Constants.L1_CHAIN_ID;

        CrossChainExample l2Example = CrossChainExample(l2ExampleAddr);

        // prepare some test message data
        bytes memory messageData = abi.encodeWithSelector(CrossChainExample.echo.selector, "Hello from L1");

        vm.startBroadcast(userPk);

        bytes32 requestId = l2Example.sendCrossChainRequest(l1ChainId, l1ExampleAddr, 0, messageData);

        console2.log("sent message from t1->l1 with requestId:", vm.toString(requestId));

        vm.stopBroadcast();
    }
}
