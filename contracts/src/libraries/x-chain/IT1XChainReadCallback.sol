/**
 * @title IT1XChainReadCallback
 * @notice Interface for contracts receiving cross-chain read results
 */
interface IT1XChainReadCallback {
    /**
     * @notice Called when a cross-chain read response is received
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    function onT1XChainReadResult(bytes32 requestId, bytes calldata result) external;
}
