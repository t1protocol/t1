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
     * @param targetContract Address of contract to read from
     * @param callData Function selector and arguments
     * @return Encoded message
     */
    function encodeRead(
        bytes32 requestId,
        address targetContract,
        bytes memory callData
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(true, requestId, targetContract, callData);
    }

    /**
     * @notice Encodes a read response message
     * @param requestId Unique identifier for the request
     * @param result Result data from the read operation
     * @return Encoded message
     */
    function encodeReadResult(bytes32 requestId, bytes memory result) internal pure returns (bytes memory) {
        return abi.encode(false, requestId, result);
    }

    /**
     * @notice Decodes a T1 message
     * @param message The message to decode
     * @return isRequest Whether this is a request (true) or response (false)
     * @return requestId Unique identifier for the request
     * @return data Additional data (varies based on isRequest)
     */
    function decode(bytes memory message)
        internal
        pure
        returns (bool isRequest, bytes32 requestId, bytes memory data)
    {
        (isRequest, requestId, data) = abi.decode(message, (bool, bytes32, bytes));
    }
}
