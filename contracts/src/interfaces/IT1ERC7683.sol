// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    IOriginSettler,
    IDestinationSettler,
    GaslessCrossChainOrder,
    OnchainCrossChainOrder
} from "../interfaces/IERC7683.sol";

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

    error ZeroAddress();
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
    error InvalidFillAuthorization();

    /// @notice Initiates a pull-based settlement verification for an order
    /// @param destinationDomain The domain of the destination chain
    /// @param orderId The ID of the order to verify
    /// @return requestId The ID of the read request
    function verifySettlement(uint32 destinationDomain, bytes32 orderId) external payable returns (bytes32 requestId);

    /// @notice Initiates a refund verification for an expired order
    /// @dev A 30 seconds delay have been added fill deadline to avoid any race condition issue
    /// @param orderId The ID of the order to verify for refund
    /// @return requestId The ID of the read request
    function verifyRefund(bytes32 orderId) external payable returns (bytes32 requestId);

    /// @notice Use result of proof of read to handle the order depending on the result
    /// Also enforce auction winner bid if the orderId has closed auction.
    /// @param encodedProofOfRead The encoded proof of read which is formatted as following:
    /// abi.encode(uint256 batchIndex, bytes32 requestId, uint256 position, bytes result, bytes proof)
    function handleReadResultWithProof(bytes calldata encodedProofOfRead) external;

    /// @notice Refunds a batch of expired GaslessCrossChainOrders on the chain where the orders were opened.
    /// This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
    /// @param _orders An array of GaslessCrossChainOrders to refund.
    /// @param _proofs Array of encoded proofs of read to verify orders are not settled
    function refund(GaslessCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external;

    /// @notice Refunds a batch of expired OnchainCrossChainOrder on the chain where the orders were opened.
    /// This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
    /// @param _orders An array of OnchainCrossChainOrders to refund.
    /// @param _proofs Array of encoded proofs of read to verify orders are not settled
    function refund(OnchainCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external;

    /// @notice Retrieves the status of a filled order by its ID
    /// @dev Returns encoded settlement data if the order has filler data, otherwise returns empty bytes
    /// @param orderId The unique identifier of the order to query
    /// @return Encoded settlement message containing order IDs and filler data, or empty bytes if order has no filler
    /// data
    function getFilledOrderStatus(bytes32 orderId) external view returns (bytes memory);
}
