// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import "../src/mocks/T1MessengerMock.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// solhint-disable no-console

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DeployT1L1MessengerMock is Script {
    uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    T1MessengerMock messengerMock;

    function run() external {

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        deployMessengerMock();

        vm.stopBroadcast();
    }

    function deployMessengerMock() internal {
        messengerMock = new T1MessengerMock();

        logAddress("T1L2_MESSENGER_MOCK_ADDRESS", address(messengerMock));
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
