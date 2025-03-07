// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { IT1Messenger } from "../IT1Messenger.sol";

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

/**
 * @title T1XChainRead
 * @notice Facilitates reading data from contracts on other chains through t1
 */
contract T1XChainRead is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // ============ Constants ============

    uint32 internal constant DEFAULT_GAS_LIMIT = 1_000_000;

    // ============ Events ============

    /**
     * @notice Emitted when a cross-chain read request is made
     * @param requestId Unique identifier for the request
     * @param destinationDomain Domain ID of the target chain
     * @param targetContract Address of the contract to read from
     * @param callData The encoded function call
     * @param callback Address that will receive the response
     */
    event ReadRequested(
        bytes32 indexed requestId,
        uint32 indexed destinationDomain,
        address targetContract,
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

    /// @notice The T1 messenger contract used for cross-chain communication
    IT1Messenger public immutable messenger;

    /// @notice The local domain ID
    uint32 public immutable localDomain;

    /// @notice Address of the counterpart T1XChainRead on other chains
    address public counterpart;

    /// @notice Maps request IDs to their callback addresses
    mapping(bytes32 => address) public callbacks;

    // ============ Errors ============

    error OnlyMessenger();
    error OnlyCounterpart();
    error InvalidCallback();
    error ZeroAddress();

    // ============ Modifiers ============

    modifier onlyMessenger() {
        if (msg.sender != address(messenger)) revert OnlyMessenger();
        _;
    }

    modifier onlyCounterpart() {
        if (messenger.xDomainMessageSender() != counterpart) revert OnlyCounterpart();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Sets up the T1XChainRead contract
     * @param _messenger Address of the T1 messenger contract
     * @param _localDomain ID of the local domain
     */
    constructor(address _messenger, uint32 _localDomain) {
        if (_messenger == address(0)) revert ZeroAddress();

        messenger = IT1Messenger(_messenger);
        localDomain = _localDomain;

        _disableInitializers();
    }

    // ============ Initializers ============

    /**
     * @notice Initializes the contract
     * @param _counterpart Address of the counterpart contract on other chains
     */
    function initialize(address _counterpart) external initializer {
        if (_counterpart == address(0)) revert ZeroAddress();

        counterpart = _counterpart;

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    // ============ External Functions ============

    /**
     * @notice Initiates a cross-chain read request
     * @param destinationDomain Domain ID of the target chain
     * @param targetContract Address of the contract to read from
     * @param callData The encoded function call (selector + arguments)
     * @param callback Address that will receive the response
     * @return requestId Unique identifier for tracking this request
     */
    function requestRead(
        uint32 destinationDomain,
        address targetContract,
        bytes calldata callData,
        address callback
    )
        external
        nonReentrant
        returns (bytes32 requestId)
    {
        if (callback.code.length == 0) revert InvalidCallback();

        requestId = keccak256(
            abi.encodePacked(
                block.chainid, destinationDomain, targetContract, callData, callback, block.timestamp, msg.sender
            )
        );

        callbacks[requestId] = callback;

        bytes memory message = T1Message.encodeRead(requestId, targetContract, callData);

        bytes memory outerMessage = abi.encodeWithSelector(
            T1XChainRead.handle.selector, localDomain, TypeCasts.addressToBytes32(address(this)), message
        );

        messenger.sendMessage(
            counterpart,
            0, // No value transfer
            outerMessage,
            DEFAULT_GAS_LIMIT,
            uint64(destinationDomain)
        );

        emit ReadRequested(requestId, destinationDomain, targetContract, callData, callback);

        return requestId;
    }

    /**
     * @notice Handles incoming messages from other chains
     * @param _origin Origin domain of the message
     * @param _sender Sender address from the origin domain
     * @param _message The encoded message
     */
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external onlyMessenger {
        address senderAddress = TypeCasts.bytes32ToAddress(_sender);

        if (senderAddress != counterpart) revert OnlyCounterpart();

        (bool isRequest, bytes32 requestId, bytes memory data) = T1Message.decode(_message);

        if (isRequest) {
            _handleReadRequest(requestId, data, _origin);
        } else {
            _handleReadResponse(requestId, data);
        }
    }

    /**
     * @notice Updates the counterpart address
     * @param _counterpart New counterpart address
     */
    function setCounterpart(address _counterpart) external onlyOwner {
        if (_counterpart == address(0)) revert ZeroAddress();
        counterpart = _counterpart;
    }

    // ============ Internal Functions ============

    /**
     * @notice Handles an incoming read request
     * @param requestId Unique identifier for the request
     * @param data Encoded data containing target contract and calldata
     * @param origin Domain identifier of the origin chain where request came from
     */
    function _handleReadRequest(bytes32 requestId, bytes memory data, uint32 origin) internal {
        (address targetContract, bytes memory callData) = abi.decode(data, (address, bytes));

        (, bytes memory result) = targetContract.staticcall(callData);

        bytes memory responseMessage = T1Message.encodeReadResult(requestId, result);

        bytes memory outerMessage = abi.encodeWithSelector(
            T1XChainRead.handle.selector, localDomain, TypeCasts.addressToBytes32(address(this)), responseMessage
        );

        messenger.sendMessage(
            counterpart,
            0, // No value transfer
            outerMessage,
            DEFAULT_GAS_LIMIT,
            uint64(origin)
        );
    }

    /**
     * @notice Handles an incoming read response
     * @param requestId Unique identifier for the original request
     * @param result The result data from the read operation
     */
    function _handleReadResponse(bytes32 requestId, bytes memory result) internal {
        address callback = callbacks[requestId];

        // If there's a valid callback, forward the result
        if (callback != address(0)) {
            delete callbacks[requestId];

            IT1XChainReadCallback(callback).onT1XChainReadResult(requestId, result);
        }

        emit ReadResult(requestId, result);
    }
}
