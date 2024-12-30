// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { IL2T1MessengerCallback, IERC165Upgradeable } from "./IL2T1MessengerCallback.sol";
import { IL2T1Messenger } from "../../L2/IL2T1Messenger.sol";

/// @title L2T1MessengerCallback
/// @notice Base contract for handling callbacks from L2T1Messenger cross-chain messages
/// @dev Contracts that want to send messages via L2T1Messenger.sendMessage() must inherit this contract
/// to receive callbacks about the message delivery status. The contract implements ERC165 interface
/// detection which L2T1Messenger uses to verify callback support.
abstract contract L2T1MessengerCallback is IL2T1MessengerCallback {
    /**
     * Errors *
     */

    /// @notice used when caller of onT1MessageCallback is not T1 protocol
    error Unauthorized();

    /// @notice used when nonce passed to onT1MessageCallback is not a pending request in this contract
    error UnknownRequest(uint256 nonce);

    /// @notice used when a reentrancy call is made
    error ReentrantCall();

    /// @notice used when a zero address is provided for the messenger contract
    error NoZeroAddress();

    /**
     * Variables *
     */

    /// @notice The L2T1Messenger contract used for sending cross-chain messages
    /// @dev This is set immutably in the constructor and used to verify callbacks come from the protocol
    IL2T1Messenger public immutable L2_MESSENGER;

    /// @notice For preventing reentrancy attacks
    bool private _processingCallback;

    /// @notice Tracks pending requests
    mapping(uint256 nonce => bool isPending) public pendingRequests;

    modifier onlyProtocol(uint64 chainId) {
        address verifier = L2_MESSENGER.verifierContracts(chainId);
        if (msg.sender != verifier) {
            revert Unauthorized();
        }
        _;
    }

    modifier nonReentrant() {
        if (_processingCallback) revert ReentrantCall();
        _processingCallback = true;
        _;
        _processingCallback = false;
    }

    /**
     * Constructor *
     */

    /// @notice Constructs a new L2T1MessengerCallback contract
    /// @param messenger The address of the L2T1Messenger contract that will be used for sending messages
    /// @dev The messenger address is stored immutably and used to verify callbacks come from the protocol
    constructor(IL2T1Messenger messenger) {
        if (address(messenger) == address(0)) revert NoZeroAddress();
        L2_MESSENGER = messenger;
    }

    /**
     * External Functions *
     */

    /// @inheritdoc IL2T1MessengerCallback
    function onT1MessageCallback(
        uint64 chainId,
        uint256 nonce,
        bool success,
        bytes32 txHash,
        bytes memory result
    )
        external
        payable
        override
        onlyProtocol(chainId)
        nonReentrant
    {
        if (!pendingRequests[nonce]) {
            revert UnknownRequest(nonce);
        }
        delete pendingRequests[nonce];
        _handleCallbackResult(nonce, success, txHash, result);
    }

    /// @inheritdoc IL2T1MessengerCallback
    function sendMessage(
        address to,
        uint256 value,
        bytes memory message,
        uint256 gasLimit,
        uint64 destChainId,
        address callbackAddress
    )
        external
        payable
        override
        returns (uint256 nonce)
    {
        nonce = L2_MESSENGER.sendMessage{ value: msg.value }(to, value, message, gasLimit, destChainId, callbackAddress);
        pendingRequests[nonce] = true;
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable virtual { }

    /**
     * Public View Functions *
     */

    /// @inheritdoc IERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IL2T1MessengerCallback).interfaceId
            || interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    /**
     * Internal Functions *
     */

    /// @notice Internal function that must be implemented by inheriting contracts to handle message callback results
    /// @param requestId The unique identifier of the original message request
    /// @param success Whether the message was successfully delivered and executed on the destination chain
    /// @param txHash The transaction hash of the message execution on the destination chain
    /// @param result The execution result data returned from the destination chain
    function _handleCallbackResult(
        uint256 requestId,
        bool success,
        bytes32 txHash,
        bytes memory result
    )
        internal
        virtual;
}
