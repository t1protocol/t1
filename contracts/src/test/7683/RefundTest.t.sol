// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";
import { BaseTest } from "./BaseTest.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { OrderData, OrderEncoder } from "../../libraries/7683/OrderEncoder.sol";
import { GaslessCrossChainOrder, OnchainCrossChainOrder, ResolvedCrossChainOrder } from "../../interfaces/IERC7683.sol";

contract RefundTest is BaseTest {
    event Refund(bytes32[] orderIds);
    event Refunded(bytes32 indexed orderId, address receiver);

    T1ERC7683 internal settlerContract;
    T1XChainReader internal mockXChainReader;

    uint32 internal FILL_DEADLINE_EXPIRED;
    uint32 internal FILL_DEADLINE_NOT_EXPIRED;

    OrderData internal defaultOrderData;

    function setUp() public override {
        super.setUp();
        __T1TestBase_setUp();

        vm.warp(1000);
        FILL_DEADLINE_EXPIRED = uint32(block.timestamp - 100);
        FILL_DEADLINE_NOT_EXPIRED = uint32(block.timestamp + 3600);

        address mockProver = makeAddr("mockProver");
        mockXChainReader = new T1XChainReader(mockProver);

        T1ERC7683 implementation = new T1ERC7683(permit2, address(mockXChainReader), origin, auctionWitness);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation), address(admin), abi.encodeWithSelector(T1ERC7683.initialize.selector, counterpart)
        );

        settlerContract = T1ERC7683(address(proxy));
        _t1ERC7683 = settlerContract;

        defaultOrderData = OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(vegeta),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            minAmountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: TypeCasts.addressToBytes32(counterpart),
            fillDeadline: FILL_DEADLINE_EXPIRED,
            closedAuction: false,
            data: ""
        });

        vm.prank(kakaroto);
        inputToken.approve(address(settlerContract), type(uint256).max);
    }

    function test_successfulRefundOnchainOrder() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        // Verify order is opened
        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        // Mock the xChainReader requestRead to return a mock requestId
        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        // Verify refund request
        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);

        // Verify order status changed to REFUND_REQUESTED
        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUND_REQUESTED));

        // Verify refundReadRequestToOrderId mapping is set
        assertEq(settlerContract.refundReadRequestToOrderId(expectedRequestId), orderId);

        // Mock the xChainReader to return our mock proof (empty result = not filled)
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        uint256 balanceBefore = inputToken.balanceOf(kakaroto);
        uint256 contractBalanceBefore = inputToken.balanceOf(address(settlerContract));

        vm.expectEmit();
        emit Refunded(orderId, kakaroto);

        settlerContract.refund(orders, proofs);

        // Verify order status changed to REFUNDED
        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUNDED));

        assertEq(inputToken.balanceOf(kakaroto), balanceBefore + amount);
        assertEq(inputToken.balanceOf(address(settlerContract)), contractBalanceBefore - amount);
    }

    function test_successfulRefundGaslessOrder() public {
        // Approve permit2 for gasless order
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint32 openDeadline = uint32(block.timestamp + 100);
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(settlerContract),
            kakaroto,
            uint64(origin),
            orderData,
            defaultOrderData.senderNonce,
            openDeadline,
            FILL_DEADLINE_EXPIRED,
            OrderEncoder.orderDataType()
        );

        bytes memory originFillerData = new bytes(0);
        ResolvedCrossChainOrder memory resolvedOrder = settlerContract.resolveFor(order, originFillerData);

        bytes memory sig = _getSignature(
            address(settlerContract),
            settlerContract.witnessHash(resolvedOrder),
            address(inputToken),
            order.nonce,
            defaultOrderData.amountIn,
            openDeadline,
            kakarotoPK
        );

        vm.prank(vegeta);
        settlerContract.openFor(order, sig, new bytes(0));

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);

        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUND_REQUESTED));

        assertEq(settlerContract.refundReadRequestToOrderId(expectedRequestId), orderId);

        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        uint256 balanceBefore = inputToken.balanceOf(kakaroto);
        uint256 contractBalanceBefore = inputToken.balanceOf(address(settlerContract));

        vm.expectEmit();
        emit Refunded(orderId, kakaroto);

        settlerContract.refund(orders, proofs);

        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUNDED));

        assertEq(inputToken.balanceOf(kakaroto), balanceBefore + amount);
        assertEq(inputToken.balanceOf(address(settlerContract)), contractBalanceBefore - amount);
    }

    function test_verifyRefundRevertIfStillValid() public {
        // Create order data with non-expired deadline
        OrderData memory notExpiredOrderData = defaultOrderData;
        notExpiredOrderData.fillDeadline = FILL_DEADLINE_NOT_EXPIRED;
        bytes memory orderData = OrderEncoder.encode(notExpiredOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_NOT_EXPIRED, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(notExpiredOrderData);

        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        vm.expectRevert(abi.encodeWithSignature("OrderFillNotExpired()"));
        settlerContract.verifyRefund(orderId);
    }

    function test_verifyRefundRevertIfOrderNotOpened() public {
        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        vm.prank(kakaroto);
        vm.expectRevert();
        settlerContract.verifyRefund(orderId);
    }

    function test_revertIfRefundNotRequested() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        // Verify order is opened but refund is not requested
        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        // Mock the xChainReader to return empty result (order not filled)
        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        vm.expectRevert(IT1ERC7683.InvalidRequest.selector);
        settlerContract.refund(orders, proofs);
    }

    function test_verifyRefundRevertIfAlreadyRefunded() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());
        vm.prank(kakaroto);
        settlerContract.open(order);
        bytes32 orderId = OrderEncoder.id(defaultOrderData);
        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );
        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );
        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";
        settlerContract.refund(orders, proofs);

        // Try to refund the order a second time
        vm.expectRevert();
        settlerContract.verifyRefund(orderId);
    }

    function test_refundRevertIfParamLengthMismatchWithOnChainOrder() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](2);
        orders[0] = order;
        orders[1] = order;

        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        vm.expectRevert(abi.encodeWithSignature("LengthMismatch()"));
        settlerContract.refund(orders, proofs);
    }

    function test_refundRevertIfParamLengthMismatchWithGasslessOrder() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        GaslessCrossChainOrder memory gaslessOrder = _prepareGaslessOrder(
            address(settlerContract),
            kakaroto,
            uint64(origin),
            orderData,
            1,
            uint32(block.timestamp + 100),
            FILL_DEADLINE_EXPIRED,
            OrderEncoder.orderDataType()
        );

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](2);
        orders[0] = gaslessOrder;
        orders[1] = gaslessOrder;

        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        vm.expectRevert(abi.encodeWithSignature("LengthMismatch()"));
        settlerContract.refund(orders, proofs);
    }

    function test_refundRevertIfOrderFilled() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);

        // Mock the xChainReader to return a proof that indicates the order is filled
        bytes memory innerMessage = abi.encode(true, new bytes32[](0), new bytes[](0)); // filled = true
        bytes memory result = abi.encode(innerMessage);

        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, result)
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        vm.expectRevert(IT1ERC7683.OrderAlreadySettled.selector);
        settlerContract.refund(orders, proofs);
    }

    function test_refundWorkIfOrderNotFilled() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);

        // Mock the xChainReader to return a proof that indicates the order is not filled
        bytes memory innerMessage = abi.encode(false, new bytes32[](0), new bytes[](0)); // filled = false
        bytes memory result = abi.encode(innerMessage);

        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, result)
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        uint256 balanceBefore = inputToken.balanceOf(kakaroto);
        uint256 contractBalanceBefore = inputToken.balanceOf(address(settlerContract));

        vm.expectEmit();
        emit Refunded(orderId, kakaroto);

        settlerContract.refund(orders, proofs);

        assertEq(uint8(settlerContract.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUNDED));

        assertEq(inputToken.balanceOf(kakaroto), balanceBefore + amount);
        assertEq(inputToken.balanceOf(address(settlerContract)), contractBalanceBefore - amount);
    }

    function test_refundRevertIfExpectedOrderDoesNotMatch() public {
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        bytes32 mockRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(mockRequestId)
        );

        // Verify refund request (this sets readRequestToOrderId[expectedRequestId] = orderId)
        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);

        // Mock the xChainReader to return a different requestId that doesn't match our order
        bytes32 differentRequestId = keccak256("different_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.verifyProofOfRead.selector),
            abi.encode(differentRequestId, bytes(""))
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        vm.expectRevert(IT1ERC7683.InvalidRequest.selector);
        settlerContract.refund(orders, proofs);
    }

    function test_refundRevertIfDeadlineNotPassed() public {
        OrderData memory notExpiredOrderData = defaultOrderData;
        notExpiredOrderData.fillDeadline = FILL_DEADLINE_NOT_EXPIRED;
        bytes memory orderData = OrderEncoder.encode(notExpiredOrderData);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(orderData, FILL_DEADLINE_NOT_EXPIRED, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        settlerContract.open(order);

        bytes32 orderId = OrderEncoder.id(notExpiredOrderData);

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(mockXChainReader),
            abi.encodeWithSelector(mockXChainReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.warp(notExpiredOrderData.fillDeadline + 29);
        vm.expectRevert(IT1ERC7683.OrderFillNotExpired.selector);
        vm.prank(kakaroto);
        settlerContract.verifyRefund(orderId);
    }
}
