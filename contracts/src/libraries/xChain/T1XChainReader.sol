// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IT1Messenger } from "../IT1Messenger.sol";
import { T1XChainMessage } from "./T1XChainMessage.sol";
import { WithdrawTrieVerifier } from "../verifier/WithdrawTrieVerifier.sol";

/**
 * @title T1XChainReader
 * @notice Facilitates reading data from contracts on other chains through t1
 */
contract T1XChainReader is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // ============ Events ============

    /**
     * @notice Emitted when a cross-chain read request is made
     * @param requestId Unique identifier for the request
     * @param destinationDomain Domain ID of the target chain
     * @param targetContract Address of the contract to read from
     * @param requester Address who initiated the read request
     * @param gasLimit The gas limit for the read operation
     * @param minBlock the minimum block on the target chain that you will accept the read to be executed
     * @param callData The encoded function call
     * @param nonce The nonce of the read request
     */
    event ReadRequested(
        bytes32 indexed requestId,
        uint32 indexed destinationDomain,
        address targetContract,
        address requester,
        uint256 gasLimit,
        uint64 minBlock,
        bytes callData,
        uint256 nonce
    );

    /**
     * @notice Emitted when a cross-chain read response succeeds
     * @param requestId Unique identifier for the original request
     * @param batchIndex The batch index of the read request
     */
    event ReadSucceeded(bytes32 indexed requestId, uint256 batchIndex);

    /**
     * @notice Emitted when a cross-chain read response fails with bytes revert
     * @param requestId Unique identifier for the original request
     * @param batchIndex The batch index of the read request
     * @param reason The reason the call failed
     */
    event ReadFailed(bytes32 indexed requestId, uint256 batchIndex, bytes reason);

    /**
     * @notice Emitted when a cross-chain read response fails with string revert
     * @param requestId Unique identifier for the original request
     * @param batchIndex The batch index of the read request
     * @param reason The reason the call failed
     */
    event ReadFailed(bytes32 indexed requestId, uint256 batchIndex, string reason);

    /**
     * @notice Emitted when a cross-chain read response is received
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    event ReadResult(bytes32 indexed requestId, bytes result);
    /**
     * @notice Emitted when a proof of read root is committed
     * @param batchIndex The batch index of the proof of read root
     */
    event ProofOfReadRootCommitted(uint256 batchIndex);

    // ============ State Variables ============

    /// @notice The T1 messenger contract used for cross-chain communication
    IT1Messenger public immutable messenger;

    /// @notice The T1 prover
    address public immutable prover;

    /// @notice Maps batch indices to their proof of read root
    mapping(uint256 batchIndex => bytes32 root) public proofOfReadRoots;

    struct ReadRequest {
        uint32 destinationDomain;
        address targetContract;
        uint256 gasLimit;
        uint64 minBlock;
        bytes callData;
    }

    // ============ Errors ============

    error OnlyProver();
    error OnlyCounterpart();
    error InvalidCallback();
    error ZeroAddress();

    // ============ Variables ============
    uint256 public nonce;

    // ============ Modifiers ============

    modifier onlyProver() {
        if (msg.sender != address(prover)) revert OnlyProver();
        _;
    }

    /**
     * @notice Sets up the T1XChainReader contract
     * @param _messenger Address of the T1 messenger contract
     */
    constructor(address _messenger, address _prover) {
        if (_messenger == address(0)) revert ZeroAddress();
        if (_prover == address(0)) revert ZeroAddress();

        messenger = IT1Messenger(_messenger);
        prover = _prover;
    }

    // ============ External Functions ============

    /**
     * @notice Initiates a cross-chain read request
     * @param request ReadRequest
     * @return requestId Unique identifier for tracking this request
     */
    function requestRead(ReadRequest calldata request) external payable nonReentrant returns (bytes32 requestId) {
        return _processReadRequest(
            request.destinationDomain, request.targetContract, request.gasLimit, request.minBlock, request.callData
        );
    }

    function _processReadRequest(
        uint32 destinationDomain,
        address targetContract,
        uint256 gasLimit,
        uint64 minBlock,
        bytes calldata callData
    )
        internal
        returns (bytes32 requestId)
    {
        requestId = keccak256(
            abi.encodePacked(
                block.chainid, destinationDomain, targetContract, callData, block.timestamp, msg.sender, nonce
            )
        );

        nonce++;

        bytes memory message = T1XChainMessage.encodeRead(
            destinationDomain, TypeCasts.addressToBytes32(targetContract), requestId, callData
        );

        // Using this selector to avoid hash collision
        bytes4 requestReadSelector = bytes4(keccak256("requestRead(uint32,address,uint256,uint64,bytes,address)"));

        _sendMessage(destinationDomain, targetContract, gasLimit, requestReadSelector, message);

        emit ReadRequested(requestId, destinationDomain, targetContract, tx.origin, gasLimit, minBlock, callData, nonce);
    }

    function _sendMessage(
        uint32 destinationDomain,
        address targetContract,
        uint256 gasLimit,
        bytes4 selector,
        bytes memory message
    )
        internal
    {
        bytes memory outerMessage = abi.encodePacked(selector, message);

        messenger.sendMessage{ value: msg.value }(
            targetContract,
            0, // No value transfer
            outerMessage,
            gasLimit,
            uint64(destinationDomain)
        );
    }

    /**
     * @notice Commit a new proof of read root
     * @dev Access limited to the prover
     * @param batchIndex The batch index of the read request
     * @param newRoot The root of the proof of read merkle tree
     */
    function commitProofOfReadRoot(uint256 batchIndex, bytes32 newRoot) external payable onlyProver {
        proofOfReadRoots[batchIndex] = newRoot;
        emit ProofOfReadRootCommitted(batchIndex);
    }

    function verifyProofOfRead(
        uint256 batchIndex,
        bytes32 requestId,
        uint256 position,
        bytes calldata result,
        bytes calldata proof
    )
        external
        view
        returns (bool)
    {
        bytes32 root = proofOfReadRoots[batchIndex];
        bytes32 xChainReadResultHash = keccak256(result);
        bytes32 leaf = keccak256(abi.encodePacked(xChainReadResultHash, requestId));

        return WithdrawTrieVerifier.verifyMerkleProof(root, leaf, position, proof);
    }
}
