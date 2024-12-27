// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { IL2T1MessengerCallback } from "../libraries/callbacks/IL2T1MessengerCallback.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title L2T1MessageVerifier
/// @notice Contract for verifying and forwarding cross-chain message results to users on t1
/// @dev This contract is deployed on t1 and acts as a trusted verifier for cross-chain message callbacks
/// originating from t1.
contract L2T1MessageVerifier is OwnableUpgradeable {
    /**
     * Constructor *
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(address) external initializer {
        OwnableUpgradeable.__Ownable_init();
    }


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
        bytes memory result
    )
        external
        onlyOwner
    {
        IL2T1MessengerCallback(target).onT1MessageCallback(chainId, nonce, success, txHash, result);
    }
}
