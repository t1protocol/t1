// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

/// @title IL2T1MessageVerifier
/// @notice Interface for setting message values in the L2T1MessageVerifier contract
/// @dev Only the L2T1Messenger contract should call these methods
interface IL2T1MessageVerifier {
    /// @notice Thrown when msg.value is less than required value + gas cost
    /// @param minValue The minimum value that needed to be sent
    error InsufficientMsgValue(uint256 minValue);

    /// @notice Thrown when caller is not the L2T1Messenger contract
    error OnlyMessenger();

    /// @notice Sets the values for a cross-chain message
    /// @param _value The amount of ether to be transferred cross-chain
    /// @param _gasCost The estimated gas cost for executing the message
    /// @param _nonce The unique identifier for this message
    /// @dev This method must be called with sufficient msg.value to cover both _value and _gasCost
    function setMessageValues(uint256 _value, uint256 _gasCost, uint256 _nonce) external payable;
}
