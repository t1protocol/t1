// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { IT1GatewayCallback } from "../../libraries/callbacks/IT1GatewayCallback.sol";

contract MockGatewayRecipient is IT1GatewayCallback {
    event ReceiveCall(bytes data);

    function onT1GatewayCallback(bytes memory data) external {
        emit ReceiveCall(data);
    }

    receive() external payable { }
}
