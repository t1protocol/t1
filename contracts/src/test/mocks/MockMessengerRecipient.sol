// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { L2T1MessengerCallback } from "../../libraries/callbacks/L2T1MessengerCallback.sol";
import { IL2T1Messenger } from "../../L2/IL2T1Messenger.sol";

contract MockMessengerRecipient is L2T1MessengerCallback {
    constructor(IL2T1Messenger l2Messenger) L2T1MessengerCallback(l2Messenger) { }

    event CallbackReceived(uint256 requestId, bool success, bytes32 txHash);

    function _handleCallbackResult(
        uint256 requestId,
        bool success,
        bytes32 txHash,
        bytes memory result
    )
        internal
        virtual
        override
    {
        emit CallbackReceived(requestId, success, txHash);
    }
}
