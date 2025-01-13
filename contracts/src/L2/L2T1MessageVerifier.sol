// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IL2T1MessengerCallback } from "../libraries/callbacks/IL2T1MessengerCallback.sol";
import { IL2T1MessageVerifier } from "./IL2T1MessageVerifier.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title L2T1MessageVerifier
/// @notice Contract for verifying and forwarding cross-chain message results to users on t1
/// @dev This contract is deployed on t1 and acts as a trusted verifier for cross-chain message callbacks
/// originating from t1.
contract L2T1MessageVerifier is OwnableUpgradeable, IL2T1MessageVerifier {
    /**
     * Errors *
     */
    /// @notice Thrown when the caller passes an actual gas value lower than what the user supplied
    error ActualGasExceedsUserSupplied();

    /// @notice Thrown when the contract fails to transfer fee
    error FailedToTransferValue();

    /**
     * Variables *
     */
    /// @notice amount user sent to cover cross-chain tx gas cost + value transfer
    mapping(uint256 nonce => uint256 amount) public messageAmounts;

    /// @notice estimated gas cost for execution
    mapping(uint256 nonce => uint256 gasCost) public messageGasCosts;

    /// @notice amount user wants transferred cross-chain
    mapping(uint256 nonce => uint256 value) public messageValues;

    /// @notice address of the L2T1Messenger contract
    address public L2_T1_MESSENGER;

    /**
     * Constructor *
     */
    constructor() {
        _disableInitializers();
    }

    modifier onlyMessenger() {
        require(msg.sender == L2_T1_MESSENGER, OnlyMessenger());
        _;
    }

    function initialize(address, address _l2t1Messenger) external initializer {
        L2_T1_MESSENGER = _l2t1Messenger;
        OwnableUpgradeable.__Ownable_init();
    }

    /// @inheritdoc IL2T1MessageVerifier
    function setMessageValues(uint256 _value, uint256 _gasCost, uint256 _nonce) external payable onlyMessenger {
        uint256 minRequired = _gasCost + _value;
        if (msg.value < minRequired) revert InsufficientMsgValue(minRequired);
        messageAmounts[_nonce] = msg.value;
        messageGasCosts[_nonce] = _gasCost;
        messageValues[_nonce] = _value;
    }

    receive() external payable { }

    /**
     * @notice Validates and forwards a cross-chain message callback to the target contract
     * @param chainId The destination chain ID where the message was sent
     * @param target The address of the contract to receive the callback
     * @param nonce The unique identifier for this message
     * @param success Whether the message execution was successful
     * @param txHash The transaction hash of the original message
     * @param result The result data from message execution
     */
    function validateCallback(
        uint64 chainId,
        address target,
        uint256 nonce,
        bool success,
        bytes32 txHash,
        uint256 actualGasUsed,
        bytes memory result
    )
        external
        onlyOwner
    {
        uint256 estimatedGas = messageGasCosts[nonce];
        uint256 transferAmount = messageValues[nonce];
        uint256 totalAmount = messageAmounts[nonce];

        /// @dev totalAmount - transferAmount accounts for any buffer that the user sent to cover gas costs
        /// @dev this check should never fail because txs cannot succeed if more gas was used than was supplied by the
        /// user
        if (totalAmount - transferAmount < actualGasUsed && success) revert ActualGasExceedsUserSupplied();

        if (success) {
            // pay postman their gas costs
            (bool sent,) = msg.sender.call{ value: actualGasUsed }("");
            if (!sent) revert FailedToTransferValue();

            // calculate excess to refund
            uint256 refund = totalAmount - transferAmount - actualGasUsed;
            if (refund > 0) {
                // refund excess along with callback
                IL2T1MessengerCallback(target).onT1MessageCallback{ value: refund }(
                    chainId, nonce, success, txHash, result
                );
            } else {
                // just do callback without value
                IL2T1MessengerCallback(target).onT1MessageCallback(chainId, nonce, success, txHash, result);
            }
        } else {
            // on failure, refund everything except postman costs if tx was attempted
            uint256 refund = txHash == bytes32(0) ? totalAmount : totalAmount - estimatedGas;
            IL2T1MessengerCallback(target).onT1MessageCallback{ value: refund }(chainId, nonce, success, txHash, result);
        }

        delete messageGasCosts[nonce];
        delete messageAmounts[nonce];
        delete messageValues[nonce];
    }
}
