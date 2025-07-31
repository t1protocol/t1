// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IOriginSettler, IDestinationSettler } from "../interfaces/IERC7683.sol";

interface IT1ERC7683 is IOriginSettler, IDestinationSettler {
    enum Status {
        UNKNOWN,
        OPENED,
        FILLED,
        SETTLED,
        REFUND_REQUESTED,
        REFUNDED
    }

    /**
     * @notice Represents a bid for order settlement
     * @param settlementReceiver The address that will receive the settlement on src chain
     * @param amountOut The amount of output tokens to be received on dst chain
     */
    struct Bid {
        address settlementReceiver;
        uint256 amountOut;
    }

    /**
     * @dev Represents data for an order that has been filled.
     * @param originData The origin-specific data for the order.
     * @param fillerData The filler-specific data for the order.
     */
    struct FilledOrder {
        bytes originData;
        bytes fillerData;
    }

    /**
     * @notice Emitted when an order is filled.
     * @param orderId The ID of the filled order.
     * @param originData The origin-specific data for the order.
     * @param fillerData The filler-specific data for the order.
     */
    event Filled(bytes32 indexed orderId, bytes originData, bytes fillerData);

    /**
     * @notice Emitted when a batch of orders is settled.
     * @param orderIds The IDs of the orders being settled.
     * @param ordersFillerData The filler data for the settled orders.
     */
    event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

    /**
     * @notice Emitted when a batch of orders is refunded.
     * @param orderIds The IDs of the refunded orders.
     */
    event Refund(bytes32[] orderIds);
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
     * @notice Emitted when an order is settled.
     * @param orderId The ID of the settled order.
     * @param receiver The address of the order's input token receiver.
     */
    event Settled(bytes32 indexed orderId, address receiver);
    /**
     * @notice Emitted when an order refund verification is requested
     * @param orderId The ID of the order
     * @param requestId The ID of the read request
     */
    event RefundVerificationRequested(bytes32 indexed orderId, bytes32 indexed requestId);
    /**
     * @notice Emitted when an order is refunded.
     * @param orderId The ID of the refunded order.
     * @param receiver The address of the order's input token receiver.
     */
    event Refunded(bytes32 indexed orderId, address receiver);
    /**
     * @notice Emitted when a winner bid is committed for an order
     * @param orderId The ID of the order
     * @param settlementSeceiver The address of the settlement receiver
     */
    event WinnerBidCommited(bytes32 indexed orderId, address indexed settlementSeceiver);

    error InvalidOrderId();
    error OrderFillExpired();
    error InvalidOrderDomain();
    error InvalidOrderType(bytes32 orderType);
    error InvalidOriginDomain(uint32 originDomain);
    error OrderOpenExpired();
    error InvalidOrderStatus();
    error InvalidGaslessOrderSettler();
    error InvalidGaslessOrderOrigin();
    error InvalidOrderOrigin();
    error InvalidNativeAmount();
    error AmountOutTooLow();
    error LengthMismatch();
    error OrderAlreadySettled();
    error InvalidRequest();
    error InvalidOrder();
    error OrderFillNotExpired();
    error NotEligible();
    error InvalidFill(
        address settlementReceiver, address expectedSettlementReceiver, uint256 amountOut, uint256 expectedAmountOut
    );
}
