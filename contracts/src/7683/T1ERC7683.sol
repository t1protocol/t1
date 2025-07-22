// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { GaslessCrossChainOrder, ResolvedCrossChainOrder, OnchainCrossChainOrder } from "../interfaces/IERC7683.sol";
import { BasicSwap7683 } from "./BasicSwap7683.sol";
import { Hyperlane7683Message } from "../libraries/7683/Hyperlane7683Message.sol";
import { OrderData, OrderEncoder } from "../libraries/7683/OrderEncoder.sol";
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
    /// @notice Maps request IDs to order IDs for cross-chain read requests for settlements
    mapping(bytes32 => bytes32) public settlementReadRequestToOrderId;
    /// @notice Maps request IDs to order IDs for cross-chain read requests for refunds
    mapping(bytes32 => bytes32) public refundReadRequestToOrderId;
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
    /**
     * @notice Emitted when an order refund verification is requested
     * @param orderId The ID of the order
     * @param requestId The ID of the read request
     */
    event RefundVerificationRequested(bytes32 indexed orderId, bytes32 indexed requestId);

    // ============ Upgrade Gap ============
    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Errors ============

    error LengthMismatch();
    error FunctionNotImplemented(string functionName);
    error SettlementFailed();
    error RefundFailed();
    error OrderAlreadySettled();
    error InvalidRequest();
    error InvalidOrder();
    error OrderFillNotExpired();

    /// @notice Initializes the contract with the specified dependencies
    /// @param _permit2 The address of the permit2 contract
    /// @param _xChainRead The address of the cross-chain read contract
    /// @param localDomain_ The local domain (chain id)
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

    /**
     * @notice Opens a cross-chain order
     * @dev To be called by the user
     * @dev This method must emit the Open event
     * @param _order The OnchainCrossChainOrder definition
     */
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

    /**
     * @notice Opens a gasless cross-chain order on behalf of a user.
     * @dev To be called by the filler.
     * @dev This method must emit the Open event
     * @param _order The GaslessCrossChainOrder definition
     * @param _signature The user's signature over the order
     * @param _originFillerData Any filler-defined data required by the settler
     */
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

    /// @notice Initiates a pull-based settlement verification for an order
    /// @param destinationDomain The domain of the destination chain
    /// @param orderId The ID of the order to verify
    /// @return requestId The ID of the read request
    function verifySettlement(uint32 destinationDomain, bytes32 orderId) external payable returns (bytes32 requestId) {
        requestId = _verifyFill(destinationDomain, orderId);
        settlementReadRequestToOrderId[requestId] = orderId;
        emit SettlementVerificationRequested(orderId, requestId);
    }

    function verifyRefund(bytes32 orderId) external returns (bytes32 requestId) {
        (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
        OrderData memory orderData = OrderEncoder.decode(_orderData);

        if (localDomain != orderData.originDomain) revert InvalidOrderDomain();
        if (block.timestamp <= orderData.fillDeadline + 30) revert OrderFillNotExpired();

        requestId = _verifyFill(orderData.destinationDomain, orderId);
        refundReadRequestToOrderId[requestId] = orderId;
        orderStatus[orderId] = REFUND_REQUESTED;

        emit RefundVerificationRequested(orderId, requestId);
    }

    function _verifyFill(uint32 destinationDomain, bytes32 orderId) private returns (bytes32 requestId) {
        // Check if the order exists and is in a valid state
        if (orderStatus[orderId] != OPENED) revert InvalidOrderStatus();

        // Create the calldata to check the order status on the destination chain
        bytes memory callData = abi.encodeWithSelector(this.getFilledOrderStatus.selector, orderId);

        T1XChainReader.ReadRequest memory readRequest = T1XChainReader.ReadRequest({
            destinationDomain: destinationDomain,
            targetContract: counterpart,
            minBlock: 0,
            callData: callData,
            requester: msg.sender
        });

        // Request the cross-chain read
        requestId = xChainRead.requestRead(readRequest);
    }

    /// @notice Use result of proof of read to handle the order depending on the result
    /// @param encodedProofOfRead The encoded proof of read which is formatted as following:
    /// abi.encode(uint256 batchIndex, bytes32 requestId, uint256 position, bytes result, bytes proof)
    function handleReadResultWithProof(bytes calldata encodedProofOfRead) external {
        (bytes32 requestId, bytes memory result) = xChainRead.verifyProofOfRead(encodedProofOfRead);

        bytes32 orderId = settlementReadRequestToOrderId[requestId];

        // Ensure we have a valid order
        if (orderId == bytes32(0)) revert InvalidOrder();

        delete settlementReadRequestToOrderId[requestId];

        // Check if the order is FILLED based on result length
        bool isSettled = (result.length != 0);

        // process the settlement if verified
        bytes32 status = orderStatus[orderId];
        if (isSettled && (status == OPENED || status == REFUND_REQUESTED)) {
            orderVerified[orderId] = true;
            // Get the order data to extract the destination domain and settler
            (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
            OrderData memory orderData = OrderEncoder.decode(_orderData);

            // Remove the first 32 bytes prefix of the message
            bytes memory _innerMessage = abi.decode(result, (bytes));
            (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
                abi.decode(_innerMessage, (bool, bytes32[], bytes[]));

            for (uint256 i = 0; i < _orderIds.length; i++) {
                if (_settle) {
                    // abi.decode(_ordersFillerData[i], (bytes32)) is receiver address set by solver when fill on dst
                    _handleSettleOrder(
                        orderData.destinationDomain,
                        orderData.destinationSettler,
                        _orderIds[i],
                        abi.decode(_ordersFillerData[i], (bytes32))
                    );
                }
            }
        }

        emit SettlementVerified(orderId, isSettled);
    }

    /// @notice Retrieves the local domain identifier.
    /// @dev This function overrides the `_localDomain` function from the parent contract.
    /// @return The local domain ID.
    function _localDomain() internal view override returns (uint32) {
        return localDomain;
    }

    /**
     * @notice Refunds a batch of expired GaslessCrossChainOrders on the chain where the orders were opened.
     * This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
     * @param _orders An array of GaslessCrossChainOrders to refund.
     * @param _proofs Array of encoded proofs of read to verify orders are not settled
     */
    function refund(GaslessCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external payable {
        if (_orders.length != _proofs.length) revert LengthMismatch();

        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            _verifyOrderNotFilled(orderId, _proofs[i]);
            orderIds[i] = orderId;
        }

        _refundOrders(OrderEncoder.decode(_orders[0].orderData).originDomain, orderIds);
    }

    /**
     * @notice Refunds a batch of expired OnchainCrossChainOrder on the chain where the orders were opened.
     * This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
     * @param _orders An array of OnchainCrossChainOrders to refund.
     * @param _proofs Array of encoded proofs of read to verify orders are not settled
     */
    function refund(OnchainCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external payable {
        if (_orders.length != _proofs.length) revert LengthMismatch();

        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            _verifyOrderNotFilled(orderId, _proofs[i]);
            orderIds[i] = orderId;
        }

        _refundOrders(OrderEncoder.decode(_orders[0].orderData).originDomain, orderIds);
    }

    /// @notice Refunds orders by transferring input tokens back to order senders
    /// @param originDomain The chain id of the network where intent has been created
    /// @param orderIds Ids for the orders to refund
    function _refundOrders(uint32 originDomain, bytes32[] memory orderIds) internal {
        if (originDomain != localDomain) revert InvalidOrderOrigin();

        for (uint256 i = 0; i < orderIds.length; i++) {
            bytes32 orderId = orderIds[i];

            if (orderStatus[orderId] != REFUND_REQUESTED) revert InvalidOrderStatus();
            orderStatus[orderId] = REFUNDED;

            (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
            OrderData memory orderData = OrderEncoder.decode(_orderData);

            address orderSender = TypeCasts.bytes32ToAddress(orderData.sender);
            address inputToken = TypeCasts.bytes32ToAddress(orderData.inputToken);

            _transferTokenOut(inputToken, orderSender, orderData.amountIn);

            emit Refunded(orderId, orderSender);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
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

    /**
     * @notice Verifies that an order is not filled using merkle proof
     * @param orderId The ID of the order to verify
     * @param encodedProofOfRead The encoded proof of read
     */
    function _verifyOrderNotFilled(bytes32 orderId, bytes calldata encodedProofOfRead) internal {
        (bytes32 requestId, bytes memory result) = xChainRead.verifyProofOfRead(encodedProofOfRead);

        // Verify this proof corresponds to the correct order
        bytes32 expectedOrderId = refundReadRequestToOrderId[requestId];
        if (expectedOrderId != orderId) revert InvalidRequest();

        delete settlementReadRequestToOrderId[requestId];

        // Check if the order is settled based on result length (same logic as handleReadResultWithProof)
        if (result.length == 0) return;

        // Remove the first 32 bytes prefix of the message
        bytes memory _innerMessage = abi.decode(result, (bytes));
        (bool filled,,) = abi.decode(_innerMessage, (bool, bytes32[], bytes[]));

        // Revert if the order is already settled
        if (filled) revert OrderAlreadySettled();
    }

    // ============ Internal Functions ============

    /// @notice Not implemented
    function _dispatchSettle(uint32, bytes32[] memory, bytes[] memory) internal pure override {
        revert FunctionNotImplemented("_dispatchSettle");
    }
}
