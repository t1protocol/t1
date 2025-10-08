// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import {
    OnchainCrossChainOrder,
    GaslessCrossChainOrder,
    ResolvedCrossChainOrder
} from "../../../src/interfaces/IERC7683.sol";
import { T1XChainReaderTest } from "./T1XChainReaderTest.t.sol";

contract PausableTest is T1XChainReaderBaseTestSetup {
    using TypeCasts for address;
    using TypeCasts for bytes32;

    uint256 batchIndex = 0;
    uint256 position = 0;

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();

        // Deploy T1XChainReader on both chains
        originReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(ITransparentUpgradeableProxy(address(originReader)), address(new T1XChainReader(address(this))));
        originReader.initialize(address(this));

        destinationReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)), address(new T1XChainReader(address(this)))
        );
        destinationReader.initialize(address(this));

        l1T1ERC7683 = T1ERC7683(payable(_deployProxy(address(0))));
        l2T1ERC7683 = T1ERC7683(payable(_deployProxy(address(0))));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1T1ERC7683)),
            address(new T1ERC7683(permit2, address(originReader), uint32(origin)))
        );
        l1T1ERC7683.initialize(address(l2T1ERC7683), auctionWitness);

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2T1ERC7683)),
            address(new T1ERC7683(permit2, address(destinationReader), uint32(destination)))
        );
        l2T1ERC7683.initialize(address(l1T1ERC7683), auctionWitness);
    }

    function test_pauseAndUnpause() public {
        // Test that only owner can pause
        vm.prank(address(0xbeef));
        vm.expectRevert();
        l1T1ERC7683.pauseOpen();

        // Test pause by owner
        l1T1ERC7683.pauseOpen();
        assertTrue(l1T1ERC7683.openPaused(), "Contract should be paused");

        // Test that only owner can unpause
        vm.prank(address(0xbeef));
        vm.expectRevert();
        l1T1ERC7683.unpauseOpen();

        // Test unpause by owner
        l1T1ERC7683.unpauseOpen();
        assertFalse(l1T1ERC7683.openPaused(), "Contract should be unpaused");

        // Test that only SETTLE_PAUSER_ROLE can pause settlement operations
        vm.prank(address(0xbeef));
        vm.expectRevert();
        l1T1ERC7683.pauseSettle();

        // Test pause settlement operations by role holder
        l1T1ERC7683.pauseSettle();
        assertTrue(l1T1ERC7683.settlePaused(), "Settlement operations should be paused");

        // Test that only SETTLE_PAUSER_ROLE can unpause settlement operations
        vm.prank(address(0xbeef));
        vm.expectRevert();
        l1T1ERC7683.unpauseSettle();

        // Test unpause settlement operations by role holder
        l1T1ERC7683.unpauseSettle();
        assertFalse(l1T1ERC7683.settlePaused(), "Settlement operations should be unpaused");
    }

    function test_pauseAndUnpauseEvents() public {
        // Test pause event
        vm.expectEmit(true, true, true, true);
        emit IT1ERC7683.OpenPaused();
        l1T1ERC7683.pauseOpen();

        // Test unpause event
        vm.expectEmit(true, true, true, true);
        emit IT1ERC7683.OpenUnpaused();
        l1T1ERC7683.unpauseOpen();

        // Test settle pause event
        vm.expectEmit(true, true, true, true);
        emit IT1ERC7683.SettlePaused();
        l1T1ERC7683.pauseSettle();

        // Test settle unpause event
        vm.expectEmit(true, true, true, true);
        emit IT1ERC7683.SettleUnpaused();
        l1T1ERC7683.unpauseSettle();
    }

    function test_canOpenWhenNotPaused() public {
        OrderData memory orderData = _prepareOrderData(amount);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), type(uint256).max);
        l1T1ERC7683.open(order);
        vm.stopPrank();

        bytes32 orderId = OrderEncoder.id(orderData);
        IT1ERC7683.Status status = l1T1ERC7683.orderStatus(orderId);
        assertEq(uint8(status), uint8(IT1ERC7683.Status.OPENED));
    }

    function test_canOpenForWhenNotPaused() public {
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint32 openDeadline = uint32(block.timestamp + 100);
        OrderData memory orderData = _prepareOrderData(amount);
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(l1T1ERC7683),
            kakaroto,
            orderData.originDomain,
            OrderEncoder.encode(orderData),
            orderData.senderNonce,
            openDeadline,
            orderData.fillDeadline,
            OrderEncoder.orderDataType()
        );
        bytes memory originFillerData = new bytes(0);

        ResolvedCrossChainOrder memory resolvedOrder = l1T1ERC7683.resolveFor(order, originFillerData);
        bytes memory sig = _getSignature(
            address(l1T1ERC7683),
            l1T1ERC7683.witnessHash(resolvedOrder),
            orderData.inputToken.bytes32ToAddress(),
            order.nonce,
            orderData.amountIn,
            openDeadline,
            kakarotoPK
        );

        vm.prank(vegeta);
        l1T1ERC7683.openFor(order, sig, new bytes(0));

        bytes32 orderId = OrderEncoder.id(orderData);
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));
    }

    function test_canSettleWhenNotPaused() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Ensure settlement operations are not paused
        assertFalse(l1T1ERC7683.settlePaused(), "Settlement should not be paused");

        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
    }

    function test_cannotOpenWhenPaused() public {
        l1T1ERC7683.pauseOpen();

        OrderData memory orderData = _prepareOrderData(amount);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), type(uint256).max);
        vm.expectRevert(IT1ERC7683.OpenOperationsPaused.selector);
        l1T1ERC7683.open(order);
        vm.stopPrank();
    }

    function test_cannotOpenForWhenPaused() public {
        l1T1ERC7683.pauseOpen();

        OrderData memory orderData = _prepareOrderData(amount);
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(l1T1ERC7683),
            kakaroto,
            uint64(origin),
            OrderEncoder.encode(orderData),
            1, // permitNonce
            uint32(block.timestamp + 100), // openDeadline
            orderData.fillDeadline,
            OrderEncoder.orderDataType()
        );

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), type(uint256).max);
        vm.expectRevert(IT1ERC7683.OpenOperationsPaused.selector);
        l1T1ERC7683.openFor(order, "", "");
        vm.stopPrank();
    }

    function test_cannotSettleWhenPaused() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Pause settlement operations
        l1T1ERC7683.pauseSettle();

        vm.expectRevert(IT1ERC7683.SettleOperationsPaused.selector);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_cannotRefundWhenPaused() public {
        uint32 deadline = 1000; // Past deadline for testing refund
        OrderData memory defaultOrderData = OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(vegeta),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            minAmountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: TypeCasts.addressToBytes32(address(l2T1ERC7683)),
            fillDeadline: deadline,
            closedAuction: false,
            data: ""
        });
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, deadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), type(uint256).max);
        l1T1ERC7683.open(order);
        vm.stopPrank();

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        // Mock the xChainReader requestRead to return a mock requestId
        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(originReader),
            abi.encodeWithSelector(originReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.warp(2000); // Set block.timestamp to 2000
        vm.prank(kakaroto);
        l1T1ERC7683.verifyRefund(orderId);
        vm.mockCall(
            address(originReader),
            abi.encodeWithSelector(originReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        l1T1ERC7683.pauseSettle(); // Pause settlement operations

        vm.expectRevert(IT1ERC7683.SettleOperationsPaused.selector);
        l1T1ERC7683.refund(orders, proofs);
    }

    function test_cannotRefundForWhenPaused() public {
        vm.warp(2000); // Set block.timestamp to 2000
        uint32 deadline = 1000; // Past deadline for testing refund
        OrderData memory defaultOrderData = _prepareOrderData(amount);
        defaultOrderData.fillDeadline = deadline;
        bytes memory orderData = OrderEncoder.encode(defaultOrderData);

        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(l1T1ERC7683),
            kakaroto,
            uint64(origin),
            orderData,
            defaultOrderData.senderNonce,
            1_000_000_000,
            deadline,
            OrderEncoder.orderDataType()
        );

        bytes memory originFillerData = new bytes(0);
        ResolvedCrossChainOrder memory resolvedOrder = l1T1ERC7683.resolveFor(order, originFillerData);

        bytes memory sig = _getSignature(
            address(l1T1ERC7683),
            l1T1ERC7683.witnessHash(resolvedOrder),
            address(inputToken),
            order.nonce,
            defaultOrderData.amountIn,
            1_000_000_000,
            kakarotoPK
        );

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);
        vm.prank(vegeta);
        l1T1ERC7683.openFor(order, sig, new bytes(0));

        bytes32 orderId = OrderEncoder.id(defaultOrderData);

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(
            address(originReader),
            abi.encodeWithSelector(originReader.requestRead.selector),
            abi.encode(expectedRequestId)
        );

        vm.warp(2000); // Set block.timestamp to 2000
        vm.prank(kakaroto);
        l1T1ERC7683.verifyRefund(orderId);

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUND_REQUESTED));

        assertEq(l1T1ERC7683.refundReadRequestToOrderId(expectedRequestId), orderId);

        vm.mockCall(
            address(originReader),
            abi.encodeWithSelector(originReader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = "mock_proof";

        l1T1ERC7683.pauseSettle(); // Pause settlement operations

        vm.expectRevert(IT1ERC7683.SettleOperationsPaused.selector);
        l1T1ERC7683.refund(orders, proofs);
    }
}
