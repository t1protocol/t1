// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IL2T1Messenger } from "./IL2T1Messenger.sol";
import { L2MessageQueue } from "./predeploys/L2MessageQueue.sol";

import { T1Constants } from "../libraries/constants/T1Constants.sol";
import { AddressAliasHelper } from "../libraries/common/AddressAliasHelper.sol";
import { T1MessengerBase } from "../libraries/T1MessengerBase.sol";
import { IL2T1MessengerCallback } from "../libraries/callbacks/IL2T1MessengerCallback.sol";

import { IERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

// solhint-disable reason-string
// solhint-disable not-rely-on-time

/// @title L2T1Messenger
/// @notice The `L2T1Messenger` contract can:
///
/// 1. send messages from layer 2 to other supported chains, including layer 1 and layer 2s;
/// 2. relay messages from layer 1 layer 2;
/// 3. drop expired message due to sequencer problems.
///
/// @dev It should be a predeployed contract on layer 2 and should hold infinite amount
/// of Ether (Specifically, `uint256(-1)`), which can be initialized in Genesis Block.
contract L2T1Messenger is T1MessengerBase, IL2T1Messenger {
    /**
     *
     * Errors *
     *
     */
    /// @dev used when user tries to send message to an unsupported chain
    error InvalidDestinationChain();

    /// @dev used when owner tries to set this chain as a supported chain for cross chain messaging
    error CannotSupportCurrentChain();

    /// @notice used when caller of sendMessage does not implement the IL2T1MessengerCallback interface
    error UnsupportedSenderInterface();

    /// @dev Thrown when msg.value is less than the required fee for sending a cross-chain message
    error InsufficientMsgValue(uint256 minValue);

    /// @dev Thrown when the contract fails to transfer fee to the fee vault
    error FailedToDeductFee();

    /// @dev Thrown when the contract fails to refund excess fee to the refund address
    error FailedToRefundFee();

    /**
     *
     * Constants *
     *
     */

    /// @notice The address of L2MessageQueue.
    address public immutable messageQueue;

    /**
     *
     * Variables *
     *
     */

    /// @notice Mapping from L2 message hash to the timestamp when the message is sent.
    mapping(bytes32 => uint256) public messageSendTimestamp;

    /// @notice Mapping from L1 message hash to a boolean value indicating if the message has been successfully
    /// executed.
    mapping(bytes32 => bool) public isL1MessageExecuted;

    /// @notice Maps chain ID to true, if the chain is supported.
    mapping(uint64 chainId => bool isSupported) private _isSupportedDest;

    /// @notice mapping of verifiers that provide the result of the cross-chain transaction to the caller
    mapping(uint64 chainId => address verifier) public verifierContracts;

    /// @notice A list of supported destination chains.
    uint64[] private _chainIds;

    /// @notice The next nonce to be assigned to an L2 -> L2 message
    uint256 private _nextL2MessageNonce;

    /// @dev The storage slots used by previous versions of this contract.
    uint256[2] private __used;

    /**
     *
     * Constructor *
     *
     */
    constructor(address _counterpart, address _messageQueue) T1MessengerBase(_counterpart) {
        if (_messageQueue == address(0)) {
            revert ErrorZeroAddress();
        }

        _disableInitializers();

        messageQueue = _messageQueue;
    }

    function initialize(address, uint64[] memory chainIds) external initializer {
        T1MessengerBase.__T1MessengerBase_init(address(0));
        for (uint256 i = 0; i < chainIds.length; i++) {
            _addChain(chainIds[i]);
        }
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IL2T1Messenger
    function sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit,
        uint64 _destChainId
    )
        external
        payable
        override
        whenNotPaused
        returns (uint256 nonce)
    {
        nonce = _sendMessage(_to, _value, _message, _gasLimit, _destChainId, _msgSender());
    }

    /// @inheritdoc IL2T1Messenger
    function sendMessage(
        address _to,
        uint256 _value,
        bytes calldata _message,
        uint256 _gasLimit,
        uint64 _destChainId,
        address _callbackAddress
    )
        external
        payable
        override
        whenNotPaused
        returns (uint256 nonce)
    {
        nonce = _sendMessage(_to, _value, _message, _gasLimit, _destChainId, _callbackAddress);
    }

    /// @inheritdoc IL2T1Messenger
    function relayMessage(
        address _from,
        address _to,
        uint256 _value,
        uint256 _nonce,
        bytes memory _message
    )
        external
        override
        whenNotPaused
    {
        // It is impossible to deploy a contract with the same address, reentrance is prevented in nature.
        require(AddressAliasHelper.undoL1ToL2Alias(_msgSender()) == counterpart, "Caller is not L1T1Messenger");

        bytes32 _xDomainCalldataHash = keccak256(_encodeXDomainCalldata(_from, _to, _value, _nonce, _message));

        require(!isL1MessageExecuted[_xDomainCalldataHash], "Message was already successfully executed");

        _executeMessage(_from, _to, _value, _message, _xDomainCalldataHash);
    }

    /// @notice Add a new supported chain
    /// @param _chainId The new chain ID
    function addChain(uint64 _chainId) external whenNotPaused onlyOwner {
        _addChain(_chainId);
    }

    /// @notice Remove a supported chain
    /// @param _chainId The chain ID to remove
    function removeChain(uint64 _chainId) external whenNotPaused onlyOwner {
        _removeChain(_chainId);
    }

    /// @inheritdoc IL2T1Messenger
    function setVerifier(uint64 _chainId, address _verifier) external whenNotPaused onlyOwner {
        verifierContracts[_chainId] = _verifier;
    }

    /**
     *
     * Public View Functions *
     *
     */
    /// @notice returns the chain ID that this contract is deployed to
    function chainId() public view returns (uint64) {
        return uint64(block.chainid);
    }

    /// @notice returns whether the provided chain ID is supported as a destination
    function isSupportedDest(uint64 chainId_) public view returns (bool) {
        if (chainId_ == T1Constants.ETH_CHAIN_ID) return true; // Ethereum always supported
        return _isSupportedDest[chainId_];
    }

    /**
     *
     * Internal Functions *
     *
     */

    /// @dev Internal function to send cross domain message.
    /// @param _to The address of account who receive the message.
    /// @param _value The amount of ether passed when call target contract.
    /// @param _message The content of the message.
    /// @param _gasLimit Optional gas limit to complete the message relay on corresponding chain.
    /// @param _destChainId The chain ID for which the message is bound.
    /// @param _callbackAddress The address of account who will receive the callback and refunded fee.
    /// @return _nonce The unique ID assigned to this request
    function _sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit,
        uint64 _destChainId,
        address _callbackAddress
    )
        internal
        nonReentrant
        returns (uint256 _nonce)
    {
        if (!isSupportedDest(_destChainId)) revert InvalidDestinationChain();

        uint256 _refund = _checkAndSendRefund(_value, _gasLimit, _destChainId, _callbackAddress);

        _nonce = _initializeMessage(_destChainId, _to, _value, _message);

        // handle eth refund if needed
        if (_refund > 0) {
            _sendRefund(_callbackAddress, _refund);
        }

        emit SentMessage(_callbackAddress, _to, _value, _nonce, _gasLimit, _message, _destChainId);
    }

    /// @dev Internal function to execute a L1 => L2 message.
    /// @param _from The address of the sender of the message.
    /// @param _to The address of the recipient of the message.
    /// @param _value The msg.value passed to the message call.
    /// @param _message The content of the message.
    /// @param _xDomainCalldataHash The hash of the message.
    function _executeMessage(
        address _from,
        address _to,
        uint256 _value,
        bytes memory _message,
        bytes32 _xDomainCalldataHash
    )
        internal
    {
        // @note check more `_to` address to avoid attack in the future when we add more gateways.
        require(_to != messageQueue, "Forbid to call message queue");
        _validateTargetAddress(_to);

        // @note This usually will never happen, just in case.
        require(_from != xDomainMessageSender, "Invalid message sender");

        xDomainMessageSender = _from;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = _to.call{ value: _value }(_message);
        // reset value to refund gas.
        xDomainMessageSender = T1Constants.DEFAULT_XDOMAIN_MESSAGE_SENDER;

        if (success) {
            isL1MessageExecuted[_xDomainCalldataHash] = true;
            emit RelayedMessage(_xDomainCalldataHash);
        } else {
            emit FailedRelayedMessage(_xDomainCalldataHash);
        }
    }

    /// @notice Handles fee calculation, collection and refunds for cross-chain messages
    /// @param _value The amount of native tokens to send with the message
    /// @param _gasLimit The gas limit for executing the message on the destination chain
    /// @param _destChainId The ID of the destination chain
    /// @param _callbackAddress The address that will receive any fee refunds
    /// @return refund The amount of excess fees to be refunded
    /// @dev For L1 messages, verifies msg.value matches _value. For L2, calculates fees and verifies sufficient
    /// msg.value.
    function _checkAndSendRefund(
        uint256 _value,
        uint256 _gasLimit,
        uint64 _destChainId,
        address _callbackAddress
    )
        internal
        returns (uint256 refund)
    {
        if (_isDestinationEthereum(_destChainId)) {
            if (msg.value != _value) revert InsufficientMsgValue(_value);
            return 0;
        }

        if (!_isCallbackSupported(_callbackAddress)) revert UnsupportedSenderInterface();

        uint256 fee = L2MessageQueue(messageQueue).estimateCrossDomainMessageFee(_gasLimit, _destChainId);
        if (msg.value < fee + _value) revert InsufficientMsgValue(fee + _value);

        if (fee > 0) {
            (bool success,) = feeVault.call{ value: fee }("");
            if (!success) revert FailedToDeductFee();
        }

        unchecked {
            refund = msg.value - fee - _value;
        }
    }

    /// @notice Initializes a cross-chain message and generates a unique nonce
    /// @param _destChainId The ID of the destination chain
    /// @param _to The address of the recipient on the destination chain
    /// @param _value The amount of native tokens to send with the message
    /// @param _message The message data to send
    /// @return nonce The unique identifier assigned to this message
    /// @dev For L1 messages, uses the message queue index as nonce. For L2, increments internal counter.
    function _initializeMessage(
        uint64 _destChainId,
        address _to,
        uint256 _value,
        bytes memory _message
    )
        internal
        returns (uint256 nonce)
    {
        nonce = _isDestinationEthereum(_destChainId)
            ? L2MessageQueue(messageQueue).nextMessageIndex()
            : _nextL2MessageNonce++;

        bytes32 hash = keccak256(_encodeXDomainCalldata(msg.sender, _to, _value, nonce, _message));

        if (messageSendTimestamp[hash] != 0) revert("Duplicated message");
        messageSendTimestamp[hash] = block.timestamp;

        if (_isDestinationEthereum(_destChainId)) {
            L2MessageQueue(messageQueue).appendMessage(hash);
        }
    }

    /// @notice Internal helper to refund excess fees to the specified address
    /// @param _to The address to receive the refund
    /// @param _amount The amount of ETH to refund
    /// @dev Reverts with FailedToRefundFee if the refund transfer fails
    function _sendRefund(address _to, uint256 _amount) internal {
        (bool success,) = _to.call{ value: _amount }("");
        if (!success) revert FailedToRefundFee();
    }

    function _addChain(uint64 _chainId) private {
        if (_chainId == chainId()) {
            revert CannotSupportCurrentChain();
        }
        _isSupportedDest[_chainId] = true;
        emit DestinationChainAdded(_chainId);
    }

    function _removeChain(uint64 _chainId) private {
        _isSupportedDest[_chainId] = false;
        emit DestinationChainRemoved(_chainId);
    }

    /// @notice Checks if an account implements the IL2T1MessengerCallback interface
    /// @dev Uses ERC165 interface detection, returns false if the check reverts
    /// @param account The address to check for callback support
    /// @return bool True if the account implements IL2T1MessengerCallback, false otherwise
    function _isCallbackSupported(address account) internal view returns (bool) {
        try IERC165Upgradeable(account).supportsInterface(T1Constants.INTERFACE_ID_ICALLBACK) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    function _isDestinationEthereum(uint64 _destChainId) internal pure returns (bool) {
        return _destChainId == T1Constants.ETH_CHAIN_ID;
    }
}
