// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IT1Messenger } from "../libraries/IT1Messenger.sol";

interface IL2T1Messenger is IT1Messenger {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when the maximum number of times each message can fail in L2 is updated.
    /// @param oldMaxFailedExecutionTimes The old maximum number of times each message can fail in L2.
    /// @param newMaxFailedExecutionTimes The new maximum number of times each message can fail in L2.
    event UpdateMaxFailedExecutionTimes(uint256 oldMaxFailedExecutionTimes, uint256 newMaxFailedExecutionTimes);

    /// @notice Emitted when a new destination chain is added to the supported chains mapping
    /// @param chainId The ID of the chain that was added as a supported destination
    event DestinationChainAdded(uint64 indexed chainId);

    /// @notice Emitted when a destination chain is removed from the supported chains mapping
    /// @param chainId The ID of the chain that was removed as a supported destination
    event DestinationChainRemoved(uint64 indexed chainId);

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @notice execute L1 => L2 message
    /// @dev Make sure this is only called by privileged accounts.
    /// @param from The address of the sender of the message.
    /// @param to The address of the recipient of the message.
    /// @param value The msg.value passed to the message call.
    /// @param nonce The nonce of the message to avoid replay attack.
    /// @param message The content of the message.
    function relayMessage(address from, address to, uint256 value, uint256 nonce, bytes calldata message) external;
}
