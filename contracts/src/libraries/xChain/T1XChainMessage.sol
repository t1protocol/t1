// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title T1XChainMessage
 * @dev Helper library for encoding/decoding T1 cross-chain messages
 */
library T1XChainMessage {
    /**
     * @notice Encodes a read request message
     * @param originDomain The domain from which the message originates
     * @param sender The address of the sender on the origin domain
     * @param requestId Unique identifier for the request
     * @param callData Function selector and arguments
     * @return Encoded message
     */
    function encodeRead(
        uint32 originDomain,
        bytes32 sender,
        bytes32 requestId,
        bytes memory callData
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(originDomain, sender, requestId, callData);
    }

    /**
     * @notice Decodes a T1 message
     * @param message The message to decode
     * @return originDomain The domain from which the message originates
     * @return sender The address of the sender on the origin domain
     * @return requestId Unique identifier for the request
     * @return data Additional data (varies based on isRequest)
     */
    function decodeResponse(bytes memory message)
        internal
        pure
        returns (uint32 originDomain, bytes32 sender, bytes32 requestId, bytes memory data)
    {
        (originDomain, sender, requestId, data) = abi.decode(message, (uint32, bytes32, bytes32, bytes));
    }
}
