// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Hyperlane7683Message } from "intents-framework/libs/Hyperlane7683Message.sol";
import { BasicSwap7683 } from "intents-framework/BasicSwap7683.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { IT1Messenger } from "../libraries/IT1Messenger.sol";
import { T1XChainRead, IT1XChainReadCallback } from "../libraries/x-chain/T1XChainRead.sol";

/**
 * @title t1_7683_PullBased
 * @author t1 Labs
 * @notice This contract extends BasicSwap7683 with pull-based settlement using t1 cross-chain reads
 * @dev Implements both push-based messaging and pull-based verification for orders
 */
contract t1_7683_PullBased is BasicSwap7683, OwnableUpgradeable, IT1XChainReadCallback {
    // ============ Constants ============

    uint32 internal constant DEFAULT_GAS_LIMIT = 1_000_000;

    uint32 public immutable localDomain;

    IT1Messenger public immutable messenger;

    T1XChainRead public immutable xChainRead;

    address public counterpart;

    // ============ State Variables ============

    /// @notice Maps request IDs to order IDs for cross-chain read requests
    mapping(bytes32 => bytes32) public readRequestToOrderId;

    /// @notice Maps order IDs to verification status
    mapping(bytes32 => bool) public orderVerified;

    // ============ Events ============

    /**
     * @notice Emitted when an order settlement verification is requested
     * @param orderId The ID of the order
     * @param requestId The ID of the read request
     */
    event SettlementVerificationRequested(bytes32 indexed orderId, bytes32 indexed requestId);

    /**
     * @notice Emitted when an order settlement is verified
     * @param orderId The ID of the order
     * @param isSettled Whether the order is settled
     */
    event SettlementVerified(bytes32 indexed orderId, bool isSettled);

    // ============ Upgrade Gap ============

    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Errors ============

    error OnlyMessenger();
    error OnlyXChainRead();
    error FunctionNotImplemented(string functionName);
    error EthNotAllowed();

    // ============ Modifiers ============

    modifier onlyMessenger() {
        if (_msgSender() != address(messenger)) revert OnlyMessenger();
        _;
    }

    modifier onlyXChainRead() {
        if (msg.sender != address(xChainRead)) revert OnlyXChainRead();
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the contract with the specified dependencies
    /// @param _messenger The address of the messenger contract
    /// @param _permit2 The address of the permit2 contract
    /// @param _xChainRead The address of the cross-chain read contract
    /// @param localDomain_ The local domain
    constructor(
        address _messenger,
        address _permit2,
        address _xChainRead,
        uint32 localDomain_
    )
        BasicSwap7683(_permit2)
    {
        messenger = IT1Messenger(_messenger);
        xChainRead = T1XChainRead(_xChainRead);
        localDomain = localDomain_;
    }

    // ============ External Functions ============

    /// @notice Initializes the contract
    /// @param _counterpart the counterpart contract on another chain
    function initialize(address _counterpart) external initializer {
        counterpart = _counterpart;
        __Ownable_init();
    }

    /// @notice Handles an incoming message
    /// @param _origin The origin domain
    /// @param _sender The sender address
    /// @param _message The message
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external payable onlyMessenger {
        _handle(_origin, _sender, _message);
    }

    /// @notice Initiates a pull-based settlement verification for an order
    /// @param destinationDomain The domain of the destination chain
    /// @param destinationSettler The address of the destination settler
    /// @param orderId The ID of the order to verify
    /// @return requestId The ID of the read request
    function verifySettlement(
        uint32 destinationDomain,
        address destinationSettler,
        bytes32 orderId
    )
        external
        returns (bytes32 requestId)
    {
        // Check if the order exists and is in a valid state
        if (orderStatus[orderId] != OPENED) revert InvalidOrderStatus();

        // Create the calldata to check the order status on the destination chain
        bytes memory callData = abi.encodeWithSelector(this.getFilledOrderStatus.selector, orderId);

        // Request the cross-chain read
        requestId = xChainRead.requestRead(destinationDomain, destinationSettler, callData, address(this));

        readRequestToOrderId[requestId] = orderId;

        emit SettlementVerificationRequested(orderId, requestId);

        return requestId;
    }

    /// @notice Callback function for cross-chain read results
    /// @param requestId The ID of the read request
    /// @param result The result of the read
    function onT1XChainReadResult(bytes32 requestId, bytes calldata result) external override onlyXChainRead {
        bytes32 orderId = readRequestToOrderId[requestId];

        // Ensure we have a valid order
        if (orderId == bytes32(0)) return;

        delete readRequestToOrderId[requestId];

        // Check if the order is FILLED based on result length
        bool isSettled = (result.length != 0);

        orderVerified[orderId] = isSettled;

        // process the settlement if verified
        if (isSettled && orderStatus[orderId] == OPENED) {
            _handle(uint32(0), bytes32(0), result);
        }

        emit SettlementVerified(orderId, isSettled);
    }

    function getFilledOrderStatus(bytes32 orderId) public view returns (bytes memory) {
        FilledOrder memory filledOrder = filledOrders[orderId];
        bytes memory orderStatus;
        if (filledOrder.fillerData.length != 0) {
            bytes32[] memory _orderIds = new bytes32[](1);
            _orderIds[0] = orderId;

            bytes[] memory _ordersFillerData = new bytes[](1);
            _ordersFillerData[0] = filledOrder.fillerData;
            orderStatus = Hyperlane7683Message.encodeSettle(_orderIds, _ordersFillerData);
        }
        return orderStatus;
    }

    // ============ Internal Functions ============

    /// @notice Not implemented
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
        revert FunctionNotImplemented("_dispatchSettle");
    }

    /// @notice Not implemented
    /// @param _originDomain The domain to which the refund message is sent.
    /// @param _orderIds The IDs of the orders to refund.
    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        revert FunctionNotImplemented("_dispatchRefund");
    }

    /// @notice Handles incoming messages
    /// @dev Decodes the message and processes settlement or refund operations accordingly
    /// @dev _originDomain The domain from which the message originates (unused in this implementation)
    /// @dev _sender The address of the sender on the origin domain (unused in this implementation)
    /// @param _message The encoded message received via t1
    function _handle(uint32, bytes32, bytes calldata _message) internal {
        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            Hyperlane7683Message.decode(_message);

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(_orderIds[i], abi.decode(_ordersFillerData[i], (bytes32)));
            } else {
                _handleRefundOrder(_orderIds[i]);
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
