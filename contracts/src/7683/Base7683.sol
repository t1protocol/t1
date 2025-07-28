// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPermit2, ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    IOriginSettler,
    IDestinationSettler,
    Output,
    FillInstruction
} from "../interfaces/IERC7683.sol";
import { OrderData, OrderEncoder } from "../libraries/7683/OrderEncoder.sol";

/**
 * @title Base7683
 * @notice Implements the ERC7683 standard for cross-chain order resolution, filling, settlement, and refunding.
 * @author BootNode
 * @dev Contains logic for managing orders without requiring specifics of the order data type.
 * Notice that settling and refunding is not described in the ERC7683 but it is included here to provide a common
 * interface for solvers to use.
 */
abstract contract Base7683 is IOriginSettler, IDestinationSettler {
    // ============ Libraries ============
    using SafeERC20 for IERC20;

    error InvalidOrderId();
    error OrderFillExpired();
    error InvalidOrderDomain();
    error InvalidOrderType(bytes32 orderType);
    error InvalidOriginDomain(uint32 originDomain);

    // ============ Constants ============
    /// @notice The instance of the Permit2 contract.
    IPermit2 public immutable PERMIT2;

    /// @notice Type hash used for encoding ResolvedCrossChainOrder.
    bytes32 public constant RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH = keccak256(
        "ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)"
    );

    /// @notice The witness type string used in PERMIT2 transactions.
    string public constant witnessTypeString =
        "ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)TokenPermissions(address token,uint256 amount)";

    /// @notice Possible statuses for an order. Other possible statuses should be defined in the inheriting contract.
    bytes32 public constant UNKNOWN = "";
    bytes32 public constant OPENED = "OPENED";
    bytes32 public constant FILLED = "FILLED";
    /// @notice Status constant indicating that an order has been settled.
    bytes32 public constant SETTLED = "SETTLED";
    /// @notice Status constant indicating that a refund has been requested for this order.
    bytes32 public constant REFUND_REQUESTED = "REFUND_REQUESTED";
    /// @notice Status constant indicating that an order has been refunded.
    bytes32 public constant REFUNDED = "REFUNDED";

    // ============ Structs ============
    /**
     * @dev Represents data for an order that has been filled.
     * @param originData The origin-specific data for the order.
     * @param fillerData The filler-specific data for the order.
     */
    struct FilledOrder {
        bytes originData;
        bytes fillerData;
    }

    // ============ Public Storage ============

    /// @notice Tracks the used nonces for each address.
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice Stores the resolved orders by their ID.
    mapping(bytes32 orderId => bytes orderData) public openOrders;

    /// @notice Tracks filled orders and their associated data.
    mapping(bytes32 orderId => FilledOrder filledOrder) public filledOrders;

    /// @notice Tracks the status of each order by its ID.
    mapping(bytes32 orderId => bytes32 status) public orderStatus;

    // ============ Upgrade Gap ============
    /// @dev Reserved space for future storage variables to ensure upgradeability.
    uint256[47] private __GAP;

    // ============ Events ============
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
     * @notice Emitted when a nonce is invalidated for an address.
     * @param owner The address whose nonce was invalidated.
     * @param nonce The invalidated nonce.
     */
    event NonceInvalidation(address indexed owner, uint256 nonce);

    // ============ Errors ============

    error OrderOpenExpired();
    error InvalidOrderStatus();
    error InvalidGaslessOrderSettler();
    error InvalidGaslessOrderOrigin();
    error InvalidNonce();
    error InvalidOrderOrigin();
    error InvalidNativeAmount();
    error AmountOutTooLow();

    // ============ Constructor ============
    /**
     * @notice Initializes the contract with the given Permit2 contract address.
     * @param _permit2 The address of the Permit2 contract.
     */
    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
    }

    // ============ Initializers ============

    // ============ External Functions ============

    /**
     * @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param _order The GaslessCrossChainOrder definition
     * NOT USED originFillerData Any filler-defined data required by the settler
     * @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolveFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _originFillerData
    )
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder)
    {
        (_resolvedOrder,,) = _resolveOrder(_order, _originFillerData);
    }

    /**
     * @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param _order The OnchainCrossChainOrder definition
     * @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolve(OnchainCrossChainOrder calldata _order)
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder)
    {
        (_resolvedOrder,,) = _resolveOrder(_order);
    }

    /**
     * @dev Resolves a GaslessCrossChainOrder.
     * @param _order The GaslessCrossChainOrder to resolve.
     * NOT USED _originFillerData Any filler-defined data required by the settler
     * @return A ResolvedCrossChainOrder structure.
     * @return The order ID.
     * @return The order nonce.
     */
    function _resolveOrder(
        GaslessCrossChainOrder memory _order,
        bytes calldata
    )
        internal
        view
        returns (ResolvedCrossChainOrder memory, bytes32, uint256)
    {
        return _resolvedOrder(
            _order.orderDataType, _order.user, _order.openDeadline, _order.fillDeadline, _order.orderData
        );
    }

    /**
     * @notice Resolves a OnchainCrossChainOrder.
     * @param _order The OnchainCrossChainOrder to resolve.
     * @return A ResolvedCrossChainOrder structure.
     * @return The order ID.
     * @return The order nonce.
     */
    function _resolveOrder(OnchainCrossChainOrder memory _order)
        internal
        view
        returns (ResolvedCrossChainOrder memory, bytes32, uint256)
    {
        return _resolvedOrder(_order.orderDataType, msg.sender, type(uint32).max, _order.fillDeadline, _order.orderData);
    }

    /**
     * @dev Resolves an order into a ResolvedCrossChainOrder structure.
     * @param _orderType The type of the order.
     * @param _sender The sender of the order.
     * @param _openDeadline The open deadline of the order.
     * @param _fillDeadline The fill deadline of the order.
     * @param _orderData The data of the order.
     * @return resolvedOrder A ResolvedCrossChainOrder structure.
     * @return orderId The order ID.
     * @return nonce The order nonce.
     */
    function _resolvedOrder(
        bytes32 _orderType,
        address _sender,
        uint32 _openDeadline,
        uint32 _fillDeadline,
        bytes memory _orderData
    )
        internal
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce)
    {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);

        // IDEA: _orderData should not be directly typed as OrderData, it should contain information that is not
        // present on the type used for open the order. So _fillDeadline and _user should be passed as arguments
        OrderData memory orderData = OrderEncoder.decode(_orderData);

        if (orderData.originDomain != _localDomain()) revert InvalidOriginDomain(orderData.originDomain);

        // bytes32 destinationSettler = _mustHaveRemoteCounterpart(orderData.destinationDomain);

        // enforce fillDeadline into orderData
        orderData.fillDeadline = _fillDeadline;
        // enforce sender into orderData
        orderData.sender = TypeCasts.addressToBytes32(_sender);

        // this can be used by the filler to approve the tokens to be spent on destination
        Output[] memory maxSpent = new Output[](1);
        maxSpent[0] = Output({
            token: orderData.outputToken,
            amount: 0, // irrelevant as we open intent with limit price
            recipient: orderData.destinationSettler,
            chainId: orderData.destinationDomain
        });

        // this can be used by the filler know how much it can expect to receive
        Output[] memory minReceived = new Output[](1);
        minReceived[0] = Output({
            token: orderData.inputToken,
            amount: orderData.amountIn,
            recipient: bytes32(0),
            chainId: orderData.originDomain
        });

        // this can be user by the filler to know how to fill the order
        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        fillInstructions[0] = FillInstruction({
            destinationChainId: orderData.destinationDomain,
            destinationSettler: orderData.destinationSettler,
            originData: OrderEncoder.encode(orderData)
        });

        orderId = OrderEncoder.id(orderData);

        resolvedOrder = ResolvedCrossChainOrder({
            user: _sender,
            originChainId: _localDomain(),
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            orderId: orderId,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });

        nonce = orderData.senderNonce;
    }

    /**
     * @notice Fills a single leg of a particular order on the destination chain
     * @param orderId Unique order identifier for this order
     * @param originData Data emitted on the origin to parameterize the fill
     * @param fillerData Data provided by the filler to inform the amount they want to fill and the address they
     * want to receive the source chain settle on.
     * Formatted as: abi.encode(uint256 amountOut, address settlementReceiver)
     */
    function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external payable virtual {
        if (orderStatus[orderId] != UNKNOWN) revert InvalidOrderStatus();

        OrderData memory orderData = OrderEncoder.decode(originData);
        (uint256 amountOut,) = abi.decode(fillerData, (uint256, address));

        if (orderId != OrderEncoder.id(orderData)) revert InvalidOrderId();
        if (block.timestamp > orderData.fillDeadline) revert OrderFillExpired();
        if (orderData.destinationDomain != _localDomain()) revert InvalidOrderDomain();
        if (amountOut < orderData.minAmountOut) revert AmountOutTooLow();

        address outputToken = TypeCasts.bytes32ToAddress(orderData.outputToken);
        address recipient = TypeCasts.bytes32ToAddress(orderData.recipient);

        if (outputToken == address(0)) {
            if (amountOut != msg.value) revert InvalidNativeAmount();
            Address.sendValue(payable(recipient), amountOut);
        } else {
            IERC20(outputToken).safeTransferFrom(msg.sender, recipient, amountOut);
        }
        orderStatus[orderId] = FILLED;
        filledOrders[orderId] = FilledOrder(originData, fillerData);

        emit Filled(orderId, originData, fillerData);
    }

    /**
     * @notice Invalidates a nonce for the user calling the function.
     * @param _nonce The nonce to invalidate.
     */
    function invalidateNonces(uint256 _nonce) external virtual {
        _useNonce(msg.sender, _nonce);

        emit NonceInvalidation(msg.sender, _nonce);
    }

    /**
     * @notice Checks whether a given nonce is valid.
     * @param _from The address whose nonce validity is being checked.
     * @param _nonce The nonce to check.
     * @return isValid True if the nonce is valid, false otherwise.
     */
    function isValidNonce(address _from, uint256 _nonce) external view virtual returns (bool) {
        return !usedNonces[_from][_nonce];
    }

    // ============ Public Functions ============

    /**
     * @notice Computes the Permit2 witness hash for a given ResolvedCrossChainOrder.
     * @param _resolvedOrder The ResolvedCrossChainOrder to compute the witness hash for.
     * @return The computed witness hash.
     */
    function witnessHash(ResolvedCrossChainOrder memory _resolvedOrder) public pure virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH,
                _resolvedOrder.user,
                _resolvedOrder.originChainId,
                _resolvedOrder.openDeadline,
                _resolvedOrder.fillDeadline,
                _resolvedOrder.maxSpent,
                _resolvedOrder.minReceived,
                _resolvedOrder.fillInstructions
            )
        );
    }

    // ============ Internal Functions ============

    /**
     * @notice Marks a nonce as used by setting its bit in the appropriate bitmap.
     * @dev Ensures that a nonce cannot be reused by flipping the corresponding bit in the bitmap.
     * Reverts if the nonce is already used.
     * @param _from The address for which the nonce is being used.
     * @param _nonce The nonce to mark as used.
     */
    function _useNonce(address _from, uint256 _nonce) internal {
        if (usedNonces[_from][_nonce]) revert InvalidNonce();
        usedNonces[_from][_nonce] = true;
    }

    /**
     * @notice Executes a batch token transfer using the Permit2 `permitWitnessTransferFrom` method.
     * @dev Transfers tokens specified in a resolved cross-chain order to the receiver.
     * @param _resolvedOrder The resolved order specifying tokens and amounts to transfer.
     * @param _signature The user's signature for the permit.
     * @param _nonce The unique nonce associated with the order.
     * @param _receiver The address that will receive the tokens.
     */
    function _permitTransferFrom(
        ResolvedCrossChainOrder memory _resolvedOrder,
        bytes calldata _signature,
        uint256 _nonce,
        address _receiver
    )
        internal
    {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](_resolvedOrder.minReceived.length);

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](_resolvedOrder.minReceived.length);

        for (uint256 i = 0; i < _resolvedOrder.minReceived.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({
                token: TypeCasts.bytes32ToAddress(_resolvedOrder.minReceived[i].token),
                amount: _resolvedOrder.minReceived[i].amount
            });
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails({
                to: _receiver,
                requestedAmount: _resolvedOrder.minReceived[i].amount
            });
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: _nonce,
            deadline: _resolvedOrder.openDeadline
        });

        PERMIT2.permitWitnessTransferFrom(
            permit, transferDetails, _resolvedOrder.user, witnessHash(_resolvedOrder), witnessTypeString, _signature
        );
    }

    /**
     * @notice Retrieves the local domain identifier.
     * @dev To be implemented by the inheriting contract. Specifies the logic to determine the local domain.
     * @return The local domain ID.
     */
    function _localDomain() internal view virtual returns (uint32);

    /**
     * @dev Gets the ID of a GaslessCrossChainOrder.
     * @param _order The GaslessCrossChainOrder to compute the ID for.
     * @return The computed order ID.
     */
    function _getOrderId(GaslessCrossChainOrder memory _order) internal pure returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /**
     * @dev Gets the ID of an OnchainCrossChainOrder.
     * @param _order The OnchainCrossChainOrder to compute the ID for.
     * @return The computed order ID.
     */
    function _getOrderId(OnchainCrossChainOrder memory _order) internal pure returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /**
     * @dev Computes the ID of an order given its type and data.
     * @param _orderType The type of the order.
     * @param _orderData The data of the order.
     * @return orderId The computed order ID.
     */
    function _getOrderId(bytes32 _orderType, bytes memory _orderData) internal pure returns (bytes32 orderId) {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);
        OrderData memory orderData = OrderEncoder.decode(_orderData);
        orderId = OrderEncoder.id(orderData);
    }

    // Left as demo for batch filler repayment
    // /**
    //  * @notice Settles a batch of filled orders on the chain where the orders were opened.
    //  * @dev Pays the filler the amount locked when the orders were opened.
    //  * The settled status should not be changed here but rather on the origin chain. To allow the filler to retry in
    //  * case some error occurs.
    //  * Ensuring the order is eligible for settling in the origin chain is the responsibility of the caller.
    //  * @param _orderIds An array of IDs for the orders to settle.
    //  */
    // function settle(bytes32[] calldata _orderIds) external payable {
    //     bytes[] memory ordersOriginData = new bytes[](_orderIds.length);
    //     bytes[] memory ordersFillerData = new bytes[](_orderIds.length);
    //     for (uint256 i = 0; i < _orderIds.length; i += 1) {
    //         // all orders must be FILLED
    //         if (orderStatus[_orderIds[i]] != FILLED) revert InvalidOrderStatus();

    //         ordersOriginData[i] = filledOrders[_orderIds[i]].originData;
    //         ordersFillerData[i] = filledOrders[_orderIds[i]].fillerData;
    //     }

    //     _settleOrders(_orderIds, ordersOriginData, ordersFillerData);

    //     emit Settle(_orderIds, ordersFillerData);
    // }

    // /**
    //  * @dev Settles multiple orders by dispatching the settlement instructions.
    //  * The proper status of all the orders (filled) is validated on the Base7683 before calling this function.
    //  * It assumes that all orders were originated in the same originDomain so it uses the the one from the first one
    // for
    //  * dispatching the message, but if some order differs on the originDomain it can be re-settle later.
    //  * @param _orderIds The IDs of the orders to settle.
    //  * @param _ordersOriginData The original data of the orders.
    //  * @param _ordersFillerData The filler data for the orders.
    //  */
    // function _settleOrders(
    //     bytes32[] calldata _orderIds,
    //     bytes[] memory _ordersOriginData,
    //     bytes[] memory _ordersFillerData
    // )
    //     internal
    // {
    //     // at this point we are sure all orders are filled, use the first order to get the originDomain
    //     // if some order differs on the originDomain it can be re-settle later
    //     _dispatchSettle(OrderEncoder.decode(_ordersOriginData[0]).originDomain, _orderIds, _ordersFillerData);
    // }

    // /// @notice Not implemented
    // function _dispatchSettle(uint32, bytes32[] memory, bytes[] memory) internal pure {
    //     revert FunctionNotImplemented("_dispatchSettle");
    // }
}
