// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import "../src/mocks/T1MessengerMock.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Script } from "forge-std/Script.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract TriggerT1L1MessengerMock is Script {
    uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address T1L2_MESSENGER_MOCK_ADDR = vm.envAddress("T1L2_MESSENGER_MOCK_ADDRESS");

    function run() external {

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        address to = makeAddr("0xE25583099BA105D9ec0A67f5Ae86D90e50036425");
        uint256 value = 1000000000;
        bytes memory message = abi.encodeWithSignature("ping()");
        uint256 gasLimit = 10000000000000;

        T1MessengerMock(T1L2_MESSENGER_MOCK_ADDR).sendMessage(to, value, message, gasLimit);

        vm.stopBroadcast();
    }
}
