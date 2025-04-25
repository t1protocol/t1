// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console } from "forge-std/console.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Hyperlane7683Message } from "intents-framework/libs/Hyperlane7683Message.sol";
import { BasicSwap7683 } from "intents-framework/BasicSwap7683.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { IT1Chain } from "../L1/rollup/IT1Chain.sol";
import { IL1T1Messenger } from "../L1/IL1T1Messenger.sol";

/**
 * @title T1ERC7683
 * @author t1 Labs
 * @notice This contract builds on top of BasicSwap7683 as a messaging layer using t1.
 * @dev It integrates with the t1 protocol for cross-chain communication.
 */
contract T1ERC7683 is BasicSwap7683, OwnableUpgradeable {
    // ============ Constants ============
    uint32 internal constant DEFAULT_GAS_LIMIT = 1_000_000;
    uint32 public immutable localDomain;
    IL1T1Messenger public immutable messenger;
    address public counterpart;

    // ============ Structs ============
    /// @notice Struct to represent an example order
    struct IntentProof {
        // The index of the batch where the PoF belongs to.
        uint256 batchIndex;
        // The proof of fill trie root
        bytes32 proofOfFillRoot;
    }

    // ============ Upgrade Gap ============
    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Errors ============
    error OnlyMessenger();
    error EthNotAllowed();
    error BatchNotFinalized();
    error IntentProofNotFound(uint256 batchIndex, bytes32 proofOfFillRoot);
    error SettlementFailed();
    error RefundFailed();

    // ============ Modifiers ============
    modifier onlyMessenger() {
        if (_msgSender() != address(messenger)) revert OnlyMessenger();
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the t17683 contract with the specified Mailbox and PERMIT2 address.
    /// @param _messenger The address of the _messenger contract.
    /// @param _permit2 The address of the permit2 contract.
    /// @param localDomain_ The local domain.
    constructor(address _messenger, address _permit2, uint32 localDomain_) BasicSwap7683(_permit2) {
        messenger = IL1T1Messenger(_messenger);
        localDomain = localDomain_;
    }

    // ============ External Functions ============

    /// @notice Initializes the contract
    /// @param _counterpart the counterpart contract on another chain
    function initialize(address _counterpart) external initializer {
        counterpart = _counterpart;
    }

    /// @notice Handles an incoming message
    /// @param _origin The origin domain
    /// @param _sender The sender address
    /// @param _intentProof The intent proof containing the batch index and proof of fill root
    /// @param _message The message
    function handle(
        uint32 _origin,
        bytes32 _sender,
        IntentProof calldata _intentProof,
        bytes calldata _message
    )
        external
        payable
        onlyMessenger
    {
        _handle(_origin, _sender, _intentProof, _message);
    }

    // ============ Internal Functions ============

    /// @notice Dispatches a settlement message to the specified domain.
    /// @dev Encodes the settle message using Hyperlane7683Message and dispatches it via the GasRouter.
    /// @param _originDomain The domain to which the settlement message is sent.
    /// @param _orderIds The IDs of the orders to settle.
    /// @param _ordersFillerData The filler data for the orders.
    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        override
    {
        if (msg.value != 0) revert EthNotAllowed();
        bytes memory innerMessage = Hyperlane7683Message.encodeSettle(_orderIds, _ordersFillerData);
        bytes memory outerMessage = abi.encodeWithSelector(
            T1ERC7683.handle.selector, _originDomain, TypeCasts.addressToBytes32(address(this)), innerMessage
        );
        messenger.sendMessage(counterpart, 0, outerMessage, DEFAULT_GAS_LIMIT, uint64(_originDomain));
    }

    /// @notice Dispatches a refund message to the specified domain.
    /// @dev Encodes the refund message using Hyperlane7683Message and dispatches it via the GasRouter.
    /// @param _originDomain The domain to which the refund message is sent.
    /// @param _orderIds The IDs of the orders to refund.
    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        if (msg.value != 0) revert EthNotAllowed();
        bytes memory innerMessage = Hyperlane7683Message.encodeRefund(_orderIds);
        bytes memory outerMessage = abi.encodeWithSelector(
            T1ERC7683.handle.selector, _originDomain, TypeCasts.addressToBytes32(address(this)), innerMessage
        );
        messenger.sendMessage(counterpart, 0, outerMessage, DEFAULT_GAS_LIMIT, uint64(_originDomain));
    }

    /// @notice Handles incoming messages
    /// @dev Decodes the message and processes settlement or refund operations accordingly
    /// @param _messageOrigin The domain from which the message originates
    /// @param _messageSender The address of the sender on the origin domain
    /// @param _intentProof The intent proof containing the batch index and proof of fill root
    /// @param _message The encoded message received via t1
    function _handle(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        IntentProof calldata _intentProof,
        bytes calldata _message
    )
        internal
    {
        IT1Chain t1Chain = IT1Chain(IL1T1Messenger(address(messenger)).rollup());

        // Check if intent proof batch index is finalized
        if (!t1Chain.isBatchFinalized(_intentProof.batchIndex)) revert BatchNotFinalized();

        // Check intent proof exists in our rollup
        if (t1Chain.proofOfFill7683Roots(_intentProof.batchIndex) != _intentProof.proofOfFillRoot) {
            revert IntentProofNotFound(_intentProof.batchIndex, _intentProof.proofOfFillRoot);
        }

        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            Hyperlane7683Message.decode(_message);

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(
                    _messageOrigin, _messageSender, _orderIds[i], abi.decode(_ordersFillerData[i], (bytes32))
                );

                if (orderStatus[_orderIds[i]] != SETTLED) revert SettlementFailed();
            } else {
                _handleRefundOrder(_messageOrigin, _messageSender, _orderIds[i]);

                if (orderStatus[_orderIds[i]] != REFUNDED) revert RefundFailed();
            }
        }
    }

    /// @notice Retrieves the local domain identifier.
    /// @dev This function overrides the `_localDomain` function from the parent contract.
    /// @return The local domain ID.
    function _localDomain() internal view override returns (uint32) {
        return localDomain;
    }
}
