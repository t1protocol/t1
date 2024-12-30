// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import {T1L1MessengerMock} from "../src/mocks/T1L1MessengerMock.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract InitializeL1BridgeContracts is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address T1L1_MESSENGER_MOCK_ADDR = makeAddr("0x373E0B8B80A15cdf587C1263654c6B5edd195a43");

    function run() external {

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        address to = makeAddr("0xE25583099BA105D9ec0A67f5Ae86D90e50036425");
        uint256 value = 1000000000;
        bytes memory message = abi.encodeWithSignature("ping()");
        uint256 gasLimit = 10000000000000;

        T1L1MessengerMock(T1L1_MESSENGER_MOCK_ADDR).sendMessage(to, value, message, gasLimit);

        vm.stopBroadcast();
    }
}
