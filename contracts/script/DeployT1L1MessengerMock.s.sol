// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import {T1L1MessengerMock} from "../src/mocks/T1L1MessengerMock.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

// solhint-disable no-console

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DeployL1BridgeContracts is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    T1L1MessengerMock messengerMock;

    function run() external {

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        deployMessengerMock();

        vm.stopBroadcast();
    }

    function deployMessengerMock() internal {
        messengerMock = new T1L1MessengerMock();

        logAddress("T1L1_MESSENGER_MOCK", address(messengerMock));
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
