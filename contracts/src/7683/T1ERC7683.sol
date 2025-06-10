// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    GaslessCrossChainOrder,
    ResolvedCrossChainOrder,
    OnchainCrossChainOrder
} from "intents-framework/ERC7683/IERC7683.sol";
import { Hyperlane7683Message } from "intents-framework/libs/Hyperlane7683Message.sol";
import { BasicSwap7683 } from "intents-framework/BasicSwap7683.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { T1XChainReader } from "../libraries/xChain/T1XChainReader.sol";
/**
 * @title T1ERC7683
 * @author t1 Labs
 * @notice This contract extends BasicSwap7683 with pull-based settlement using t1 cross-chain reads
 * @dev Implements both push-based messaging and pull-based verification for orders
 */

contract T1ERC7683 is BasicSwap7683, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint32 public immutable localDomain;
    T1XChainReader public immutable xChainRead;
    address public counterpart;

    // ============ State Variables ============
    mapping(bytes32 requestId => uint256 batchIndex) public requestIdToBatchIndex;
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
    error FunctionNotImplemented(string functionName);
    error SettlementFailed();
    error RefundFailed();

    /// @notice Initializes the contract with the specified dependencies
    /// @param _permit2 The address of the permit2 contract
    /// @param _xChainRead The address of the cross-chain read contract
    /// @param localDomain_ The local domain
    constructor(address _permit2, address _xChainRead, uint32 localDomain_) BasicSwap7683(_permit2) {
        xChainRead = T1XChainReader(_xChainRead);
        localDomain = localDomain_;
    }

    // ============ External Functions ============

    /// @notice Initializes the contract
    /// @param _counterpart the counterpart contract on another chain
    function initialize(address _counterpart) external initializer {
        counterpart = _counterpart;
        __Ownable_init();
        __Pausable_init();
    }

    function openFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _signature,
        bytes calldata _originFillerData
    )
        external
        override
        whenNotPaused
    {
        if (block.timestamp > _order.openDeadline) revert OrderOpenExpired();
        if (_order.originSettler != address(this)) revert InvalidGaslessOrderSettler();
        if (_order.originChainId != _localDomain()) revert InvalidGaslessOrderOrigin();

        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) =
            _resolveOrder(_order, _originFillerData);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
        orderStatus[orderId] = OPENED;
        _useNonce(_order.user, nonce);

        _permitTransferFrom(resolvedOrder, _signature, _order.nonce, address(this));

        emit Open(orderId, resolvedOrder);
    }

    function open(OnchainCrossChainOrder calldata _order) external payable override whenNotPaused {
        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(_order);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
        orderStatus[orderId] = OPENED;
        _useNonce(msg.sender, nonce);

        uint256 totalValue;
        for (uint256 i = 0; i < resolvedOrder.minReceived.length; i++) {
            address token = TypeCasts.bytes32ToAddress(resolvedOrder.minReceived[i].token);
            if (token == address(0)) {
                totalValue += resolvedOrder.minReceived[i].amount;
            } else {
                IERC20(token).safeTransferFrom(msg.sender, address(this), resolvedOrder.minReceived[i].amount);
            }
        }

        if (msg.value != totalValue) revert InvalidNativeAmount();

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Initiates a pull-based settlement verification for an order
    /// @param destinationDomain The domain of the destination chain
    /// @param gasLimit The gas limit for the read operation
    /// @param orderId The ID of the order to verify
    /// @return requestId The ID of the read request
    function verifySettlement(
        uint32 destinationDomain,
        uint256 gasLimit,
        bytes32 orderId
    )
        external
        payable
        returns (bytes32 requestId)
    {
        // Check if the order exists and is in a valid state
        if (orderStatus[orderId] != OPENED) revert InvalidOrderStatus();

        // Create the calldata to check the order status on the destination chain
        bytes memory callData = abi.encodeWithSelector(this.getFilledOrderStatus.selector, orderId);

        T1XChainReader.ReadRequest memory readRequest = T1XChainReader.ReadRequest({
            destinationDomain: destinationDomain,
            targetContract: counterpart,
            gasLimit: gasLimit,
            minBlock: 0,
            callData: callData
        });

        // Request the cross-chain read
        requestId = xChainRead.requestRead{ value: msg.value }(readRequest);

        readRequestToOrderId[requestId] = orderId;

        emit SettlementVerificationRequested(orderId, requestId);
    }

    /// @notice Use result of proof of read to handle the order depending on the result
    /// @param encodedProofOfRead The encoded proof of read which is formatted as following:
    /// abi.encode(uint256 batchIndex, bytes32 requestId, uint256 position, bytes result, bytes proof)
    function handleReadResultWithProof(bytes calldata encodedProofOfRead) external {
        (bytes32 requestId, bytes memory result) = xChainRead.verifyProofOfRead(encodedProofOfRead);

        bytes32 orderId = readRequestToOrderId[requestId];

        // Ensure we have a valid order
        if (orderId == bytes32(0)) return;

        delete readRequestToOrderId[requestId];

        // Check if the order is FILLED based on result length
        bool isSettled = (result.length != 0);

        orderVerified[orderId] = isSettled;

        // process the settlement if verified
        if (isSettled && orderStatus[orderId] == OPENED) {
            // Get the order data to extract the destination domain and settler
            (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
            OrderData memory orderData = OrderEncoder.decode(_orderData);

            _handle(orderData.destinationDomain, orderData.destinationSettler, result);
        }

        emit SettlementVerified(orderId, isSettled);
    }

    function getFilledOrderStatus(bytes32 orderId) external view returns (bytes memory) {
        FilledOrder memory filledOrder = filledOrders[orderId];
        bytes memory _orderStatus;
        if (filledOrder.fillerData.length != 0) {
            bytes32[] memory _orderIds = new bytes32[](1);
            _orderIds[0] = orderId;

            bytes[] memory _ordersFillerData = new bytes[](1);
            _ordersFillerData[0] = filledOrder.fillerData;
            _orderStatus = Hyperlane7683Message.encodeSettle(_orderIds, _ordersFillerData);
        }
        return _orderStatus;
    }

    // ============ Internal Functions ============

    /// @notice Not implemented
    function _dispatchSettle(uint32, bytes32[] memory, bytes[] memory) internal pure override {
        revert FunctionNotImplemented("_dispatchSettle");
    }

    /// @notice Not implemented
    function _dispatchRefund(uint32, bytes32[] memory) internal pure override {
        revert FunctionNotImplemented("_dispatchRefund");
    }

    /// @notice Handles incoming messages
    /// @dev Decodes the message and processes settlement or refund operations accordingly
    /// @param _originDomain The domain from which the message originates
    /// @param _sender The address of the sender on the origin domain
    /// @param _message The encoded message received via t1
    function _handle(uint32 _originDomain, bytes32 _sender, bytes memory _message) internal {
        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            abi.decode(_message, (bool, bytes32[], bytes[]));

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(_originDomain, _sender, _orderIds[i], abi.decode(_ordersFillerData[i], (bytes32)));

                if (orderStatus[_orderIds[i]] != SETTLED) revert SettlementFailed();
            } else {
                _handleRefundOrder(_originDomain, _sender, _orderIds[i]);

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
