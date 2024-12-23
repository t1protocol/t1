// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IL2T1Messenger } from "./IL2T1Messenger.sol";
import { L2MessageQueue } from "./predeploys/L2MessageQueue.sol";

import { T1Constants } from "../libraries/constants/T1Constants.sol";
import { AddressAliasHelper } from "../libraries/common/AddressAliasHelper.sol";
import { T1MessengerBase } from "../libraries/T1MessengerBase.sol";

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
        T1MessengerBase.__T1MessengerBase_init(address(0), address(0));
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

        uint256 _fee;
        if (_destChainId == T1Constants.ETH_CHAIN_ID) {
            if (msg.value != _value) revert InsufficientMsgValue(_value);
            _nonce = L2MessageQueue(messageQueue).nextMessageIndex();
        } else {
            // compute and deduct the messaging fee to fee vault.
            _fee = L2MessageQueue(messageQueue).estimateCrossDomainMessageFee(_gasLimit, _destChainId);
            if (msg.value < _fee + _value) revert InsufficientMsgValue(_fee + _value);
            if (_fee > 0) {
                (bool _success,) = feeVault.call{ value: _fee }("");
                if (!_success) revert FailedToDeductFee();
            }

            _nonce = _nextL2MessageNonce;
            unchecked {
                _nextL2MessageNonce += 1;
            }
        }
        bytes32 _xDomainCalldataHash = keccak256(_encodeXDomainCalldata(_msgSender(), _to, _value, _nonce, _message));

        // normally this won't happen, since each message has different nonce, but just in case.
        require(messageSendTimestamp[_xDomainCalldataHash] == 0, "Duplicated message");
        messageSendTimestamp[_xDomainCalldataHash] = block.timestamp;

        if (_destChainId == T1Constants.ETH_CHAIN_ID) {
            L2MessageQueue(messageQueue).appendMessage(_xDomainCalldataHash);
        }

        emit SentMessage(_callbackAddress, _to, _value, _nonce, _gasLimit, _message, _destChainId);

        _checkAndSendRefund(_callbackAddress, _value, _fee);
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

    function _checkAndSendRefund(address _callbackAddress, uint256 _value, uint256 _fee) private {
        unchecked {
            uint256 _refund = msg.value - _fee - _value;
            if (_refund > 0) {
                (bool _success,) = _callbackAddress.call{ value: _refund }("");
                if (!_success) revert FailedToRefundFee();
            }
        }
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
}
