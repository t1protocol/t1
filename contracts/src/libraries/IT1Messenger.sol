// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

interface IT1Messenger {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when a cross domain message is relayed successfully.
    /// @param messageHash The hash of the message.
    event RelayedMessage(bytes32 indexed messageHash);

    /// @notice Emitted when a cross domain message is failed to relay.
    /// @param messageHash The hash of the message.
    event FailedRelayedMessage(bytes32 indexed messageHash);

    /// @notice Emitted when a t1 to L2 or t1 to L1 cross domain message is sent.
    /// @param sender The address of the sender who initiates the message. This is not necessarily msg.sender
    /// @param target The address of target contract to call.
    /// @param value The amount of value passed to the target contract.
    /// @param messageNonce The nonce of the message.
    /// @param gasLimit The optional gas limit passed to L1 or L2.
    /// @param message The calldata passed to the target contract.
    /// @param destChainId The chain ID for which the message is bound.
    /// @param messageHash The hash of the cross-chain message
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message,
        uint64 indexed destChainId,
        bytes32 messageHash
    );

    /**
     *
     * Errors *
     *
     */

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /**
     *
     * Public View Functions *
     *
     */

    /// @notice Return the sender of a cross domain message.
    function xDomainMessageSender() external view returns (address);

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @notice Send cross chain message from t1 to L2 or t1 to L1.
    /// @param target The address of account who receive the message.
    /// @param value The amount of ether passed when call target contract.
    /// @param message The content of the message.
    /// @param gasLimit Gas limit required to complete the message relay on corresponding chain.
    /// @param destChainId The ID of the chain for which the message is bound.
    function sendMessage(
        address target,
        uint256 value,
        bytes calldata message,
        uint256 gasLimit,
        uint64 destChainId
    )
        external
        payable;

    /// @notice Send cross chain message from t1 to L2 or t1 to L1.
    /// @param target The address of account who receive the message.
    /// @param value The amount of ether passed when call target contract.
    /// @param message The content of the message.
    /// @param gasLimit Gas limit required to complete the message relay on corresponding chain.
    /// @param destChainId The ID of the chain for which the message is bound.
    /// @param callbackAddress The address of account who will receive the callback and the refunded fee.
    function sendMessage(
        address target,
        uint256 value,
        bytes calldata message,
        uint256 gasLimit,
        uint64 destChainId,
        address callbackAddress
    )
        external
        payable;
}
