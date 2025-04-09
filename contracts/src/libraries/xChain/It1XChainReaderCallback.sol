// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title It1XChainReaderCallback
 * @notice Interface for contracts receiving cross-chain read results
 */
interface It1XChainReaderCallback {
    /**
     * @notice Called when a cross-chain read response is received
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    function ont1XChainReaderResult(bytes32 requestId, bytes calldata result) external;
}
