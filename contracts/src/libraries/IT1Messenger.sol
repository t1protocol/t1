// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

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
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message,
        uint64 indexed destChainId
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
}
