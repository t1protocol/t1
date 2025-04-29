// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IL1MessageQueue } from "../../L1/rollup/IL1MessageQueue.sol";
import { BaseT1XChainReader } from "./BaseT1XChainReader.sol";

/**
 * @title T1L1XChainReader
 * @notice Facilitates reading data from contracts on other chains from L1 through t1
 */
contract T1L1XChainReader is BaseT1XChainReader {
    constructor(
        address _messenger,
        address _prover,
        uint32 _localDomain
    )
        BaseT1XChainReader(_messenger, _prover, _localDomain)
    { }

    function _sendMessage(
        uint32 destinationDomain,
        address targetContract,
        bytes4 selector,
        bytes memory message
    )
        internal
        override
    {
        bytes memory outerMessage = abi.encodePacked(selector, message);

        uint256 gasLimit = IL1MessageQueue(messenger.messageQueue()).calculateIntrinsicGasFee(outerMessage);
        gasLimit = gasLimit * 12 / 10;

        messenger.sendMessage{ value: msg.value }(
            targetContract,
            0, // No value transfer
            outerMessage,
            gasLimit,
            uint64(destinationDomain)
        );
    }
}
