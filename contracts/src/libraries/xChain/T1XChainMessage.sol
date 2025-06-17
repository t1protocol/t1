// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title T1XChainMessage
 * @dev Helper library for encoding/decoding t1 cross-chain messages
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
        bytes memory callData,
        address requester
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(originDomain, sender, requestId, callData, requester);
    }
}
