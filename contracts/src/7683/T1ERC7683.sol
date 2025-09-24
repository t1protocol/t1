// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Hyperlane7683Message } from "../libraries/7683/Hyperlane7683Message.sol";
import { OrderData, OrderEncoder } from "../libraries/7683/OrderEncoder.sol";

import { IT1ERC7683 } from "../interfaces/IT1ERC7683.sol";
import {
    Output,
    FillInstruction,
    GaslessCrossChainOrder,
    ResolvedCrossChainOrder,
    OnchainCrossChainOrder
} from "../interfaces/IERC7683.sol";
import { T1Permit2 } from "./T1Permit2.sol";
import { IT1XChainReader } from "../libraries/xChain/IT1XChainReader.sol";

/// @title T1ERC7683
/// @author t1 Labs
contract T1ERC7683 is IT1ERC7683, T1Permit2, AccessControlUpgradeable, EIP712 {
    using SafeERC20 for IERC20;

    error InvalidDestinationSettler(bytes32 provided, bytes32 expected);

    /// @notice Role for pausing/unpausing open operations
    bytes32 public constant OPEN_PAUSER_ROLE = keccak256("OPEN_PAUSER_ROLE");
    /// @notice Role for pausing/unpausing settlement operations
    bytes32 public constant SETTLE_PAUSER_ROLE = keccak256("SETTLE_PAUSER_ROLE");
    /// @notice chain id
    uint32 public immutable localDomain;
    IT1XChainReader public immutable xChainRead;

    /// @notice Stores the resolved orders by their ID.
    mapping(bytes32 orderId => bytes orderData) public openOrders;
    /// @notice Tracks filled orders and their associated data.
    mapping(bytes32 orderId => FilledOrder filledOrder) public filledOrders;
    /// @notice Tracks the status of each order by its ID.
    mapping(bytes32 orderId => Status status) public orderStatus;
    mapping(bytes32 requestId => uint256 batchIndex) public requestIdToBatchIndex;
    /// @notice Maps request IDs to order IDs for cross-chain read requests for refunds
    mapping(bytes32 => bytes32) public refundReadRequestToOrderId;
    /// @notice Maps request IDs to order IDs for cross-chain read requests for settlements
    mapping(bytes32 => bytes32) public settlementReadRequestToOrderId;
    /// @notice Authorization signer for off chain auction results
    address public auctionWitness;
    /// @notice Separate pausable states
    bool public openPaused;
    bool public settlePaused;
    /// @notice Sibling settler contract
    address public counterpart;

    /// @notice Modifier to check if open operations are not paused
    modifier whenOpenNotPaused() {
        if (openPaused) revert OpenOperationsPaused();
        _;
    }

    /// @notice Modifier to check if settlement operations are not paused
    modifier whenSettleNotPaused() {
        if (settlePaused) revert SettleOperationsPaused();
        _;
    }

    /// @notice EIP-712 typehash for fill authorization
    bytes32 public constant FILL_AUTHORIZATION_TYPEHASH =
        keccak256("FillAuthorization(bytes32 orderId,address filler,uint256 amountOut)");

    /// @notice Initializes the contract with the specified dependencies
    /// @param _permit2 The address of the permit2 contract
    /// @param _xChainRead The address of the cross-chain read contract
    /// @param _localDomain The local domain (chain id)
    constructor(
        address _permit2,
        address _xChainRead,
        uint32 _localDomain
    )
        T1Permit2(_permit2)
        EIP712("T1ERC7683", "1")
    {
        xChainRead = IT1XChainReader(_xChainRead);
        localDomain = _localDomain;
    }

    /// @notice Initializes the contract
    /// @param _counterpart the counterpart contract on another chain
    /// @param _auctionWitness Address of the auction result signer
    function initialize(address _counterpart, address _auctionWitness) external initializer {
        if (_counterpart == address(0) || _auctionWitness == address(0)) revert ZeroAddress();
        counterpart = _counterpart;
        auctionWitness = _auctionWitness;
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(OPEN_PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(SETTLE_PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPEN_PAUSER_ROLE, msg.sender);
        _grantRole(SETTLE_PAUSER_ROLE, msg.sender);
    }

    /// @notice Opens a cross-chain order
    /// @dev To be called by the user
    /// @dev This method must emit the Open event
    /// @param _order The OnchainCrossChainOrder definition
    function open(OnchainCrossChainOrder calldata _order) external payable override whenOpenNotPaused {
        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(_order);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
        orderStatus[orderId] = Status.OPENED;
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

    /// @notice Opens a gasless cross-chain order on behalf of a user.
    /// @dev To be called by the filler.
    /// @dev This method must emit the Open event
    /// @param _order The GaslessCrossChainOrder definition
    /// @param _signature The user's signature over the order
    /// @param _originFillerData Any filler-defined data required by the settler
    function openFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _signature,
        bytes calldata _originFillerData
    )
        external
        override
        whenOpenNotPaused
    {
        if (block.timestamp > _order.openDeadline) revert OrderOpenExpired();
        if (_order.originSettler != address(this)) revert InvalidGaslessOrderSettler();
        if (_order.originChainId != localDomain) revert InvalidGaslessOrderOrigin();

        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) =
            _resolveOrder(_order, _originFillerData);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
        orderStatus[orderId] = Status.OPENED;
        _useNonce(_order.user, nonce);

        _permitTransferFrom(resolvedOrder, _signature, _order.nonce, address(this));

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param _order The GaslessCrossChainOrder definition
    /// NOT USED originFillerData Any filler-defined data required by the settler
    /// @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
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

    /// @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param _order The OnchainCrossChainOrder definition
    /// @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
    function resolve(OnchainCrossChainOrder calldata _order)
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder)
    {
        (_resolvedOrder,,) = _resolveOrder(_order);
    }

    /// @dev Resolves a GaslessCrossChainOrder.
    /// @param _order The GaslessCrossChainOrder to resolve.
    /// NOT USED _originFillerData Any filler-defined data required by the settler
    /// @return A ResolvedCrossChainOrder structure.
    /// @return The order ID.
    /// @return The order nonce.
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

    /// @notice Resolves a OnchainCrossChainOrder.
    /// @param _order The OnchainCrossChainOrder to resolve.
    /// @return A ResolvedCrossChainOrder structure.
    /// @return The order ID.
    /// @return The order nonce.
    function _resolveOrder(OnchainCrossChainOrder memory _order)
        internal
        view
        returns (ResolvedCrossChainOrder memory, bytes32, uint256)
    {
        return _resolvedOrder(_order.orderDataType, msg.sender, type(uint32).max, _order.fillDeadline, _order.orderData);
    }

    /// @dev Resolves an order into a ResolvedCrossChainOrder structure.
    /// @param _orderType The type of the order.
    /// @param _sender The sender of the order.
    /// @param _openDeadline The open deadline of the order.
    /// @param _fillDeadline The fill deadline of the order.
    /// @param _orderData The data of the order.
    /// @return resolvedOrder A ResolvedCrossChainOrder structure.
    /// @return orderId The order ID.
    /// @return nonce The order nonce.
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

        OrderData memory orderData = OrderEncoder.decode(_orderData);

        if (orderData.originDomain != localDomain) revert InvalidOriginDomain(orderData.originDomain);

        // Ensure destinationSettler matches counterpart
        bytes32 expectedSettler = TypeCasts.addressToBytes32(counterpart);
        if (orderData.destinationSettler != expectedSettler) {
            revert InvalidDestinationSettler(orderData.destinationSettler, expectedSettler);
        }

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
            originChainId: localDomain,
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            orderId: orderId,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });

        nonce = orderData.senderNonce;
    }

    /// @notice Fills a single leg of a particular order on the destination chain
    /// @param orderId Unique order identifier for this order
    /// @param originData Data emitted on the origin to parameterize the fill
    /// @param fillerData Data provided by the filler to inform the amount they want to fill and the address they
    /// want to receive the source chain settle on + optional auction witness signature representing the
    /// authorization for winner if closed auction
    /// Formatted as: abi.encode(uint256 amountOut, address settlementReceiver, bytes authorization)
    function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external payable virtual {
        if (orderStatus[orderId] != Status.UNKNOWN) revert InvalidOrderStatus();

        OrderData memory orderData = OrderEncoder.decode(originData);

        uint256 amountOut;
        if (orderData.closedAuction) {
            bytes memory authorization;
            (amountOut,, authorization) = abi.decode(fillerData, (uint256, address, bytes));
            _verifyAuthorization(orderId, amountOut, authorization);
        } else {
            (amountOut,) = abi.decode(fillerData, (uint256, address));
        }

        _validateFillParameters(orderId, orderData, amountOut);

        address outputToken = TypeCasts.bytes32ToAddress(orderData.outputToken);
        address recipient = TypeCasts.bytes32ToAddress(orderData.recipient);

        _executeTransfer(outputToken, recipient, amountOut);

        orderStatus[orderId] = Status.FILLED;
        filledOrders[orderId] = FilledOrder(originData, fillerData);

        emit Filled(orderId, originData, fillerData);
    }

    /// @dev Decodes filler data to extract amount and authorization
    function _decodeFillerData(bytes calldata fillerData)
        private
        pure
        returns (uint256 amountOut, bytes memory authorization)
    {
        if (fillerData.length > 64) {
            (amountOut,, authorization) = abi.decode(fillerData, (uint256, address, bytes));
        } else {
            (amountOut,) = abi.decode(fillerData, (uint256, address));
        }
    }

    /// @dev Validates fill parameters and authorization
    function _validateFillParameters(bytes32 orderId, OrderData memory orderData, uint256 amountOut) private view {
        if (orderId != OrderEncoder.id(orderData)) revert InvalidOrderId();
        if (block.timestamp > orderData.fillDeadline) revert OrderFillExpired();
        if (orderData.destinationDomain != localDomain) revert InvalidOrderDomain();
        if (amountOut < orderData.minAmountOut) revert AmountOutTooLow();
    }

    /// @dev Executes the token transfer (ETH or ERC20)
    function _executeTransfer(address outputToken, address recipient, uint256 amountOut) private {
        if (outputToken == address(0)) {
            if (amountOut != msg.value) revert InvalidNativeAmount();
            Address.sendValue(payable(recipient), amountOut);
        } else {
            IERC20(outputToken).safeTransferFrom(msg.sender, recipient, amountOut);
        }
    }

    function _verifyAuthorization(bytes32 orderId, uint256 amountOut, bytes memory authorization) private view {
        bytes32 structHash = keccak256(abi.encode(FILL_AUTHORIZATION_TYPEHASH, orderId, msg.sender, amountOut));
        bytes32 digest = _hashTypedDataV4(structHash);
        (address signer,) = ECDSA.tryRecover(digest, authorization);
        if (signer != auctionWitness) revert InvalidFillAuthorization();
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

    /// @notice Initiates a refund verification for an expired order
    /// @dev A 30 seconds delay have been added fill deadline to avoid any race condition issue
    /// @param orderId The ID of the order to verify for refund
    /// @return requestId The ID of the read request
    function verifyRefund(bytes32 orderId) external payable returns (bytes32 requestId) {
        (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
        OrderData memory orderData = OrderEncoder.decode(_orderData);

        if (localDomain != orderData.originDomain) revert InvalidOrderDomain();
        if (block.timestamp <= orderData.fillDeadline + 30) revert OrderFillNotExpired();

        requestId = _verifyFill(orderData.destinationDomain, orderId);
        refundReadRequestToOrderId[requestId] = orderId;
        orderStatus[orderId] = Status.REFUND_REQUESTED;

        emit RefundVerificationRequested(orderId, requestId);
    }

    function _verifyFill(uint32 destinationDomain, bytes32 orderId) internal returns (bytes32 requestId) {
        // Check if the order exists and is in a valid state
        if (orderStatus[orderId] != Status.OPENED) revert InvalidOrderStatus();

        // Create the calldata to check the order status on the destination chain
        bytes memory callData = abi.encodeWithSelector(this.getFilledOrderStatus.selector, orderId);

        IT1XChainReader.ReadRequest memory readRequest = IT1XChainReader.ReadRequest({
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
    /// Also enforce auction winner bid if the orderId has closed auction.
    /// @param encodedProofOfRead The encoded proof of read which is formatted as following:
    /// abi.encode(uint256 batchIndex, bytes32 requestId, uint256 position, bytes result, bytes proof)
    function handleReadResultWithProof(bytes calldata encodedProofOfRead) external whenSettleNotPaused {
        (bytes32 requestId, bytes memory result) = xChainRead.verifyProofOfRead(encodedProofOfRead);

        bytes32 orderId = settlementReadRequestToOrderId[requestId];

        // Ensure we have a valid order
        if (orderId == bytes32(0)) revert InvalidOrder();

        delete settlementReadRequestToOrderId[requestId];

        // Check if the order is FILLED based on result length
        bool isSettled = (result.length != 0);

        // process the settlement if verified
        Status status = orderStatus[orderId];
        if (isSettled && (status == Status.OPENED || status == Status.REFUND_REQUESTED)) {
            // Get the order data to extract the destination domain and settler
            (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
            OrderData memory orderData = OrderEncoder.decode(_orderData);

            // Remove the first 32 bytes prefix of the message
            bytes memory _innerMessage = abi.decode(result, (bytes));
            (bool _settled, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
                abi.decode(_innerMessage, (bool, bytes32[], bytes[]));

            for (uint256 i = 0; i < _orderIds.length; i++) {
                if (_settled) {
                    (, address settlementReceiver) = abi.decode(_ordersFillerData[i], (uint256, address));
                    _handleSettleOrder(
                        orderData.destinationDomain, orderData.destinationSettler, _orderIds[i], settlementReceiver
                    );
                }
            }
        }

        emit SettlementVerified(orderId, isSettled);
    }

    /// @dev Handles settling an individual order, should be called by the inheriting contract when receiving a setting
    /// instruction from a remote chain.
    /// @param _messageOrigin The domain from which the message originates.
    /// @param _messageSender The address of the sender on the origin domain.
    /// @param _orderId The ID of the order to settle.
    /// @param settlementReceiver The receiver address (encoded as bytes32).
    function _handleSettleOrder(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId,
        address settlementReceiver
    )
        internal
        virtual
    {
        (bool isEligible, OrderData memory orderData) = _checkOrderEligibility(_messageOrigin, _messageSender, _orderId);

        if (!isEligible) revert NotEligible();

        orderStatus[_orderId] = Status.SETTLED;

        address inputToken = TypeCasts.bytes32ToAddress(orderData.inputToken);

        _transferTokenOut(inputToken, settlementReceiver, orderData.amountIn);

        emit Settled(_orderId, settlementReceiver);
    }

    /// @notice Checks if order is eligible for settlement or refund .
    /// @dev Order must be OPENED and the message was sent from the appropriated chain and contract.
    /// @param _messageOrigin The origin domain of the message.
    /// @param _messageSender The sender identifier of the message.
    /// @param _orderId The unique identifier of the order.
    /// @return A boolean indicating if the order is valid, and the decoded OrderData structure.
    function _checkOrderEligibility(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId
    )
        internal
        virtual
        returns (bool, OrderData memory)
    {
        OrderData memory orderData;

        // check if the order is opened or asked for refund to ensure it belongs to this domain, skip otherwise
        Status status = orderStatus[_orderId];
        if (status != Status.OPENED && status != Status.REFUND_REQUESTED) return (false, orderData);

        (, bytes memory _orderData) = abi.decode(openOrders[_orderId], (bytes32, bytes));
        orderData = OrderEncoder.decode(_orderData);

        if (orderData.destinationDomain != _messageOrigin || orderData.destinationSettler != _messageSender) {
            return (false, orderData);
        }

        return (true, orderData);
    }

    /// @notice Refunds a batch of expired GaslessCrossChainOrders on the chain where the orders were opened.
    /// This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
    /// @param _orders An array of GaslessCrossChainOrders to refund.
    /// @param _proofs Array of encoded proofs of read to verify orders are not settled
    function refund(GaslessCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external whenSettleNotPaused {
        if (_orders.length != _proofs.length) revert LengthMismatch();

        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            _verifyOrderNotFilled(orderId, _proofs[i]);
            orderIds[i] = orderId;
        }

        _refundOrders(OrderEncoder.decode(_orders[0].orderData).originDomain, orderIds);
    }

    /// @notice Refunds a batch of expired OnchainCrossChainOrder on the chain where the orders were opened.
    /// This process needs a proof of read triggered by `verifyRefund` that proves the intent has not be filled.
    /// @param _orders An array of OnchainCrossChainOrders to refund.
    /// @param _proofs Array of encoded proofs of read to verify orders are not settled
    function refund(OnchainCrossChainOrder[] memory _orders, bytes[] calldata _proofs) external whenSettleNotPaused {
        if (_orders.length != _proofs.length) revert LengthMismatch();

        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            _verifyOrderNotFilled(orderId, _proofs[i]);
            orderIds[i] = orderId;
        }

        _refundOrders(OrderEncoder.decode(_orders[0].orderData).originDomain, orderIds);
    }

    /// @dev Gets the ID of a GaslessCrossChainOrder.
    /// @param _order The GaslessCrossChainOrder to compute the ID for.
    /// @return The computed order ID.
    function _getOrderId(GaslessCrossChainOrder memory _order) internal pure returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /// @dev Gets the ID of an OnchainCrossChainOrder.
    /// @param _order The OnchainCrossChainOrder to compute the ID for.
    /// @return The computed order ID.
    function _getOrderId(OnchainCrossChainOrder memory _order) internal pure returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /// @dev Computes the ID of an order given its type and data.
    /// @param _orderType The type of the order.
    /// @param _orderData The data of the order.
    /// @return orderId The computed order ID.
    function _getOrderId(bytes32 _orderType, bytes memory _orderData) internal pure returns (bytes32 orderId) {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);
        OrderData memory orderData = OrderEncoder.decode(_orderData);
        orderId = OrderEncoder.id(orderData);
    }

    /// @notice Verifies that an order is not filled using merkle proof
    /// @param orderId The ID of the order to verify
    /// @param encodedProofOfRead The encoded proof of read
    function _verifyOrderNotFilled(bytes32 orderId, bytes calldata encodedProofOfRead) internal {
        (bytes32 requestId, bytes memory result) = xChainRead.verifyProofOfRead(encodedProofOfRead);

        // Verify this proof corresponds to the correct order
        bytes32 expectedOrderId = refundReadRequestToOrderId[requestId];
        if (expectedOrderId != orderId) revert InvalidRequest();

        delete refundReadRequestToOrderId[requestId];

        // Check if the order is settled based on result length (same logic as handleReadResultWithProof)
        if (result.length == 0) return;

        // Remove the first 32 bytes prefix of the message
        bytes memory _innerMessage = abi.decode(result, (bytes));
        (bool filled,,) = abi.decode(_innerMessage, (bool, bytes32[], bytes[]));

        // Revert if the order is already settled
        if (filled) revert OrderAlreadySettled();
    }

    /// @notice Refunds orders by transferring input tokens back to order senders
    /// @param originDomain The chain id of the network where intent has been created
    /// @param orderIds Ids for the orders to refund
    function _refundOrders(uint32 originDomain, bytes32[] memory orderIds) internal {
        if (originDomain != localDomain) revert InvalidOrderOrigin();

        for (uint256 i = 0; i < orderIds.length; i++) {
            bytes32 orderId = orderIds[i];

            if (orderStatus[orderId] != Status.REFUND_REQUESTED) revert InvalidOrderStatus();
            orderStatus[orderId] = Status.REFUNDED;

            (, bytes memory _orderData) = abi.decode(openOrders[orderId], (bytes32, bytes));
            OrderData memory orderData = OrderEncoder.decode(_orderData);

            address orderSender = TypeCasts.bytes32ToAddress(orderData.sender);
            address inputToken = TypeCasts.bytes32ToAddress(orderData.inputToken);

            _transferTokenOut(inputToken, orderSender, orderData.amountIn);

            emit Refunded(orderId, orderSender);
        }
    }

    function updateAuctionWitness(address newAuctionWitness) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAuctionWitness == address(0)) revert ZeroAddress();
        emit AuctionWitnessUpdated(auctionWitness, newAuctionWitness);
        auctionWitness = newAuctionWitness;
    }

    function pauseOpen() external onlyRole(OPEN_PAUSER_ROLE) {
        openPaused = true;
        emit OpenPaused();
    }

    function unpauseOpen() external onlyRole(OPEN_PAUSER_ROLE) {
        openPaused = false;
        emit OpenUnpaused();
    }

    function pauseSettle() external onlyRole(SETTLE_PAUSER_ROLE) {
        settlePaused = true;
        emit SettlePaused();
    }

    function unpauseSettle() external onlyRole(SETTLE_PAUSER_ROLE) {
        settlePaused = false;
        emit SettleUnpaused();
    }

    /// @notice Retrieves the status of a filled order by its ID
    /// @dev Returns encoded settlement data if the order has filler data, otherwise returns empty bytes
    /// @param orderId The unique identifier of the order to query
    /// @return Encoded settlement message containing order IDs and filler data, or empty bytes if order has no filler
    /// data
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

    /// @notice Expose domain separator
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Transfers tokens or ETH out of the contract.
    /// @dev If _token is the zero address, transfers ETH using a safe method; otherwise, performs an ERC20 token
    /// transfer.
    /// @param _token The address of the token to transfer (use address(0) for ETH).
    /// @param _to The recipient address.
    /// @param _amount The amount of tokens or ETH to transfer.
    function _transferTokenOut(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0)) {
            Address.sendValue(payable(_to), _amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }
}
