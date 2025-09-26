// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IT1XChainReader {
    struct ReadRequest {
        uint32 destinationDomain;
        address targetContract;
        uint64 minBlock;
        bytes callData;
        address requester;
    }

    function initialize(address _owner) external;
    function requestRead(ReadRequest calldata request) external payable returns (bytes32 requestId);
    function commitProofOfReadRoot(uint256 batchIndex, bytes32 newRoot) external;
    function verifyProofOfRead(bytes calldata encodedProofOfRead) external view returns (bytes32, bytes memory);
    function verifyProofsOfRead(bytes[] calldata encodedProofOfRead)
        external
        view
        returns (bytes32[] memory requestIds, bytes[] memory results);
    function verifyProofOfReadWithResult(
        bytes calldata encodedProofOfRead,
        bytes calldata result
    )
        external
        view
        returns (bytes32);
    function setReadFee(uint256 _readFee) external;
    function setFeeRecipient(address _feeRecipient) external;
    function withdrawFees() external;

    function prover() external view returns (address);
    function nextBatchIndex() external view returns (uint256);
    function proofOfReadRoots(uint256 batchIndex) external view returns (bytes32);
    function readFee() external view returns (uint256);
    function feeRecipient() external view returns (address);
    function nonce() external view returns (uint256);
}
