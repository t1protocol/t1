// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {L2T1MessengerCallback} from "../callbacks/L2T1MessengerCallback.sol";
import {IL2T1Messenger} from "../../L2/IL2T1Messenger.sol";

contract AaveMessenger is L2T1MessengerCallback {
    event SupplyCompleted(uint256 nonce, bool success);
    
    constructor(IL2T1Messenger messenger) L2T1MessengerCallback(messenger) {}

    function supplyOnAave(
        address pool,
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode,
        uint256 gasLimit,
        uint64 destChainId
    ) external payable returns (uint256) {
        bytes memory message = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            asset,
            amount,
            onBehalfOf,
            referralCode
        );

        return this.sendMessage{value: msg.value}(
            pool,
            amount,
            message,
            gasLimit,
            destChainId,
            address(this)
        );
    }

    function _handleCallbackResult(
        uint256 nonce,
        bool success,
        bytes32 txHash,
        bytes memory result
    ) internal override {
        emit SupplyCompleted(nonce, success);
    }

    receive() external payable override {}
}