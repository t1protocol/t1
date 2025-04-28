// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IL1MessageQueue } from "../../L1/rollup/IL1MessageQueue.sol";
import { IT1Messenger } from "../IT1Messenger.sol";
import { T1XChainMessage } from "./T1XChainMessage.sol";
import { IT1XChainReaderCallback } from "./IT1XChainReaderCallback.sol";

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
     * @param minBlock the minimum block on the target chain that you will accept the read to be executed
     * @param callData The encoded function call
     * @param callback Address that will receive the response
     */
    event ReadRequested(
        bytes32 indexed requestId,
        uint32 indexed destinationDomain,
        address targetContract,
        uint64 minBlock,
        bytes callData,
        address indexed callback
    );

    /**
     * @notice Emitted when a cross-chain read response is received
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    event ReadResult(bytes32 indexed requestId, bytes result);

    // ============ State Variables ============

    IT1Messenger public immutable messenger;
    /// @notice The T1 messenger contract used for cross-chain communication

    /// @notice The T1 prover
    address public immutable prover;

    /// @notice The local domain ID
    uint32 public immutable localDomain;

    /// @notice Maps request IDs to their callback addresses
    mapping(bytes32 => address) public callbacks;

    struct ReadRequest {
        uint32 destinationDomain;
        address targetContract;
        uint64 minBlock;
        bytes callData;
        address callback;
    }

    // ============ Errors ============

    error OnlyProver();
    error OnlyCounterpart();
    error InvalidCallback();
    error ZeroAddress();

    // ============ Modifiers ============

    modifier onlyProver() {
        if (msg.sender != address(prover)) revert OnlyProver();
        _;
    }

    /**
     * @notice Sets up the T1XChainReader contract
     * @param _messenger Address of the T1 messenger contract
     * @param _localDomain ID of the local domain
     */
    constructor(address _messenger, address _prover, uint32 _localDomain) {
        if (_messenger == address(0)) revert ZeroAddress();

        messenger = IT1Messenger(_messenger);
        localDomain = _localDomain;
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
            request.destinationDomain, request.targetContract, request.minBlock, request.callData, request.callback
        );
    }

    function _processReadRequest(
        uint32 destinationDomain,
        address targetContract,
        uint64 minBlock,
        bytes calldata callData,
        address callback
    )
        internal
        returns (bytes32 requestId)
    {
        if (callback.code.length == 0) revert InvalidCallback();

        requestId = keccak256(
            abi.encodePacked(
                block.chainid, destinationDomain, targetContract, callData, callback, block.timestamp, msg.sender
            )
        );

        callbacks[requestId] = callback;

        bytes memory message = T1XChainMessage.encodeRead(
            destinationDomain, TypeCasts.addressToBytes32(targetContract), requestId, callData
        );

        // Using this selector to avoid hash collision
        bytes4 requestReadSelector = bytes4(keccak256("requestRead(uint32,address,uint64,bytes,address)"));

        _sendMessage(destinationDomain, targetContract, requestReadSelector, message);

        emit ReadRequested(requestId, destinationDomain, targetContract, minBlock, callData, callback);

        return requestId;
    }

    function _sendMessage(
        uint32 destinationDomain,
        address targetContract,
        bytes4 selector,
        bytes memory message
    )
        internal
    {
        bytes memory outerMessage = abi.encodePacked(selector, message);

        uint256 gasLimit = IL1MessageQueue(messenger.messageQueue()).calculateIntrinsicGasFee(outerMessage);
        // Add some buffer
        gasLimit = gasLimit * 12 / 10; // 120% of intrinsic gas

        messenger.sendMessage{ value: msg.value }(
            targetContract,
            0, // No value transfer
            outerMessage,
            gasLimit,
            uint64(destinationDomain)
        );
    }

    /**
     * @notice Handles incoming messages from other chains
     * @param _originDomain The origin domain
     * @param _sender The sender address on the target chain
     * @param _requestId The ID assigned to the request when it was dispatched
     * @param _data The data to relay to the callback contract
     */
    function handle(
        uint32 _originDomain,
        bytes32 _sender,
        bytes32 _requestId,
        bytes memory _data
    )
        external
        payable
        onlyProver
    {
        _handleReadResponse(_originDomain, _sender, _requestId, _data);
    }

    // ============ Internal Functions ============

    /**
     * @notice Handles an incoming read response
     * @param _originDomain The origin domain
     * @param _sender The sender address
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    function _handleReadResponse(
        uint32 _originDomain,
        bytes32 _sender,
        bytes32 requestId,
        bytes memory result
    )
        internal
    {
        address callback = callbacks[requestId];

        // If there's a valid callback, forward the result
        if (callback != address(0)) {
            delete callbacks[requestId];

            IT1XChainReaderCallback(callback).onT1XChainReaderResult(_originDomain, _sender, requestId, result);
        }

        emit ReadResult(requestId, result);
    }
}
