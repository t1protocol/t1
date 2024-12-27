// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { IERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

interface IL2T1MessengerCallback is IERC165Upgradeable {
    /// @notice Validates and forwards a cross-chain message callback to the target contract
    /// @param chainId The ID of the destination chain where the message was sent
    /// @param nonce The unique identifier of the original message request
    /// @param success Whether the message was successfully delivered and executed
    /// @param txHash The transaction hash of the message execution on the destination chain
    /// @param result The execution result data returned from the destination chain
    /// @dev Only callable by the owner when contract is not paused
    function onT1MessageCallback(
        uint64 chainId,
        uint256 nonce,
        bool success,
        bytes32 txHash,
        bytes memory result
    )
        external;

    /// @notice Sends a cross-chain message via the L2T1Messenger contract
    /// @param to The address of the recipient on the destination chain
    /// @param value The amount of native tokens to send with the message
    /// @param message The message data to send
    /// @param gasLimit The gas limit for executing the message on the destination chain
    /// @param destChainId The ID of the destination chain
    /// @param callbackAddress The address of account who will receive the callback and the refunded fee.
    /// @return nonce The unique identifier assigned to this message request
    /// @dev The nonce is tracked as a pending request until a callback is received
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
        returns (uint256 nonce);
}
