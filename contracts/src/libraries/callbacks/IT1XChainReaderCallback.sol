// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IT1XChainReaderCallback
 * @notice Interface for contracts receiving cross-chain read results
 */
interface IT1XChainReaderCallback {
    /**
     * @notice Called when a cross-chain read response is received
     * @param requestId The ID assigned to the request when it was dispatched
     * @param batchIndex The batch index of the read request
     * @param newRoot The root of the proof of read merkle tree
     */
    function onT1XChainReaderResult(bytes32 requestId, uint256 batchIndex, bytes32 newRoot) external;
}
