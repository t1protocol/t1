// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title T1Message
 * @dev Helper library for encoding/decoding T1 cross-chain messages
 */
library T1Message {
    /**
     * @notice Encodes a read request message
     * @param requestId Unique identifier for the request
     * @param callData Function selector and arguments
     * @return Encoded message
     */
    function encodeRead(
        bytes32 requestId,
        bytes memory callData
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(requestId, callData);
    }

    /**
     * @notice Decodes a T1 message
     * @param message The message to decode
     * @return requestId Unique identifier for the request
     * @return data Additional data (varies based on isRequest)
     */
    function decodeResponse(bytes memory message)
        internal
        pure
        returns (bytes32 requestId, bytes memory data)
    {
        (requestId, data) = abi.decode(message, (bytes32, bytes));
    }
}
