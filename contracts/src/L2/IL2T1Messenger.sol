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

    /// @notice Send cross chain message from t1 to L2 or t1 to L1.
    /// @param target The address of account who receive the message.
    /// @param value The amount of ether passed when call target contract.
    /// @param message The content of the message.
    /// @param gasLimit Gas limit required to complete the message relay on corresponding chain.
    /// @param destChainId The ID of the chain for which the message is bound.
    /// @return nonce The unique ID assigned to this request
    function sendMessage(
        address target,
        uint256 value,
        bytes calldata message,
        uint256 gasLimit,
        uint64 destChainId
    )
        external
        payable
        returns (uint256 nonce);

    /// @notice Send cross chain message from t1 to L2 or t1 to L1.
    /// @param target The address of account who receive the message.
    /// @param value The amount of ether passed when call target contract.
    /// @param message The content of the message.
    /// @param gasLimit Gas limit required to complete the message relay on corresponding chain.
    /// @param destChainId The ID of the chain for which the message is bound.
    /// @param callbackAddress The address of account who will receive the callback and the refunded fee.
    /// @return nonce The unique ID assigned to this request
    function sendMessage(
        address target,
        uint256 value,
        bytes calldata message,
        uint256 gasLimit,
        uint64 destChainId,
        address callbackAddress
    )
        external
        payable
        returns (uint256 nonce);

    /// @notice execute L1 => L2 message
    /// @dev Make sure this is only called by privileged accounts.
    /// @param from The address of the sender of the message.
    /// @param to The address of the recipient of the message.
    /// @param value The msg.value passed to the message call.
    /// @param nonce The nonce of the message to avoid replay attack.
    /// @param message The content of the message.
    function relayMessage(address from, address to, uint256 value, uint256 nonce, bytes calldata message) external;

    /// @notice Get the verifier contract address for a given chain ID
    /// @param _chainId The chain ID to get the verifier contract for
    /// @return verifier The address of the verifier contract for the given chain ID
    function verifierContracts(uint64 _chainId) external returns (address verifier);

    /// @notice Sets the verifier contract address for a specific chain
    /// @param _chainId The chain ID to set the verifier for
    /// @param _verifier The address of the verifier contract
    /// @dev Only callable by the owner when contract is not paused
    function setVerifier(uint64 _chainId, address _verifier) external;
}
