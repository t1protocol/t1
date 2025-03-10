// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "intents-framework/ERC7683/IERC7683.sol";
import { Base7683 } from "intents-framework/Base7683.sol";

import { T1XChainRead, IT1XChainReadCallback } from "../../libraries/x-chain/T1XChainRead.sol";
import { t1BasicSwapE2E } from "./t1BasicSwapE2E.t.sol";
import { IL1T1Messenger } from "../../L1/IL1T1Messenger.sol";
import { L1T1Messenger } from "../../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../../L2/L2T1Messenger.sol";
import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";
import { t1_7683_PullBased } from "../../7683/t1_7683_pull_based.sol";

contract TargetContract {
    uint256 public value;
    mapping(bytes32 => bool) public orders;

    function getOrderStatus(bytes32 _orderId) external view returns (bool) {
        return orders[_orderId];
    }

    constructor(uint256 _value) {
        value = _value;
    }

    function setValue(uint256 _value) external {
        value = _value;
    }

    function setOrderStatus(bytes32 _orderId, bool _status) external {
        orders[_orderId] = _status;
    }
}

contract CallbackContract is IT1XChainReadCallback {
    bytes32 public lastRequestId;
    bytes public lastResult;
    bool public callbackReceived;

    function onT1XChainReadResult(bytes32 requestId, bytes calldata result) external override {
        lastRequestId = requestId;
        lastResult = result;
        callbackReceived = true;
    }
}

contract T1XChainReadTest is t1BasicSwapE2E {
    using TypeCasts for address;

    T1XChainRead internal originReader;
    T1XChainRead internal destinationReader;
    TargetContract internal tc;
    CallbackContract internal callbackContract;
    t1_7683_PullBased internal l1_t1_7683_pull_based;
    t1_7683_PullBased internal l2_t1_7683_pull_based;

    function setUp() public virtual override {
        super.setUp();

        // Deploy the target contract on the destination chain
        tc = new TargetContract(42);

        // Deploy the callback contract on the origin chain
        callbackContract = new CallbackContract();

        // Deploy T1XChainRead on both chains
        originReader = T1XChainRead(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(originReader)),
            address(new T1XChainRead(address(l1t1Messenger), origin))
        );

        destinationReader = T1XChainRead(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)),
            address(new T1XChainRead(address(l2t1Messenger), destination))
        );

        // Initialize with counterparts
        originReader.initialize(address(destinationReader));
        destinationReader.initialize(address(originReader));

        l1_t1_7683_pull_based = t1_7683_PullBased(payable(_deployProxy(address(0))));
        l2_t1_7683_pull_based = t1_7683_PullBased(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1_t1_7683_pull_based)),
            address(new t1_7683_PullBased(address(l1t1Messenger), address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2_t1_7683_pull_based)),
            address(
                new t1_7683_PullBased(
                    address(l2t1Messenger), address(0), address(destinationReader), uint32(destination)
                )
            )
        );
        l1_t1_7683_pull_based.initialize(address(l2_t1_7683_pull_based));
        l2_t1_7683_pull_based.initialize(address(l1_t1_7683_pull_based));
    }

    function test_crossChainRead_getValue() public {
        // Create the calldata for reading the value
        bytes memory callData = abi.encodeWithSignature("value()");

        // Request a cross-chain read
        bytes32 requestId = originReader.requestRead(destination, address(tc), callData, address(callbackContract));

        // Verify the request was made properly
        assertEq(originReader.callbacks(requestId), address(callbackContract));

        // Handle the request on the destination chain
        {
            // Simulate the cross-chain message from L1 to L2
            bytes memory message = T1Message.encodeRead(requestId, address(tc), callData);

            bytes memory outerMessage = abi.encodeWithSelector(
                T1XChainRead.handle.selector, origin, TypeCasts.addressToBytes32(address(originReader)), message
            );

            vm.startPrank(address(l2t1Messenger));
            vm.mockCall(
                address(l2t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(originReader))
            );

            destinationReader.handle(origin, TypeCasts.addressToBytes32(address(originReader)), message);
            vm.stopPrank();
        }

        {
            // Simulate the cross-chain message from L2 to L1
            // The result would be uint256(42)
            bytes memory result = abi.encode(uint256(42));
            bytes memory message = T1Message.encodeReadResult(requestId, result);

            bytes memory outerMessage = abi.encodeWithSelector(
                T1XChainRead.handle.selector,
                destination,
                TypeCasts.addressToBytes32(address(destinationReader)),
                message
            );

            vm.startPrank(address(l1t1Messenger));
            vm.mockCall(
                address(l1t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(destinationReader))
            );

            originReader.handle(destination, TypeCasts.addressToBytes32(address(destinationReader)), message);
            vm.stopPrank();
        }

        // Verify the callback received the correct data
        assertTrue(callbackContract.callbackReceived());
        assertEq(callbackContract.lastRequestId(), requestId);

        // Verify the value was correctly read
        uint256 returnedValue = abi.decode(callbackContract.lastResult(), (uint256));
        assertEq(returnedValue, 42);
    }

    function test_settlementVerification() public {
        // First, set up an order on the destination chain
        OrderData memory orderData = _prepareOrderData();
        bytes32 orderId = OrderEncoder.id(orderData);

        // Mark the order as FILLED on the destination chain
        tc.setOrderStatus(orderId, true);

        // Create calldata for checking the order status
        bytes memory callData = abi.encodeWithSelector(TargetContract.getOrderStatus.selector, orderId);

        // Request verification of the order status
        bytes32 requestId = originReader.requestRead(destination, address(tc), callData, address(callbackContract));

        // Handle the request on the destination chain
        {
            bytes memory message = T1Message.encodeRead(requestId, address(tc), callData);

            vm.startPrank(address(l2t1Messenger));
            vm.mockCall(
                address(l2t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(originReader))
            );

            destinationReader.handle(origin, TypeCasts.addressToBytes32(address(originReader)), message);
            vm.stopPrank();
        }

        // Handle the response on the origin chain
        {
            bytes memory result = abi.encode(true); // Order is filled
            bytes memory message = T1Message.encodeReadResult(requestId, result);

            vm.startPrank(address(l1t1Messenger));
            vm.mockCall(
                address(l1t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(destinationReader))
            );

            originReader.handle(destination, TypeCasts.addressToBytes32(address(destinationReader)), message);
            vm.stopPrank();
        }

        // Verify the order status was correctly read
        bool orderFilled = abi.decode(callbackContract.lastResult(), (bool));
        assertTrue(orderFilled);
    }

    function test_settlementVerification_7683() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        uint256[] memory balancesBeforeOpen = _balances(inputToken);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // fill
        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        uint256[] memory balancesBeforeFill = _balances(outputToken);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Filled(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        destinationRouter.fill(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = destinationRouter.filledOrders(orderId);

        vm.stopPrank();

        // ~~~

        // Create calldata for checking the order status
        bytes memory callData = abi.encodeWithSignature("filledOrders(bytes32)", orderId);

        // Request verification of the order status
        bytes32 requestId = originReader.requestRead(
            destination, address(l2_t1_7683_pull_based), callData, address(l1_t1_7683_pull_based)
        );

        // Handle the request on the destination chain
        {
            bytes memory message = T1Message.encodeRead(requestId, address(l2_t1_7683_pull_based), callData);

            vm.startPrank(address(l2t1Messenger));
            vm.mockCall(
                address(l2t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(originReader))
            );

            destinationReader.handle(origin, TypeCasts.addressToBytes32(address(originReader)), message);
            vm.stopPrank();
        }

        // Handle the response on the origin chain
        {
            bytes memory result = abi.encode(true); // Order is filled
            bytes memory message = T1Message.encodeReadResult(requestId, result);

            vm.startPrank(address(l1t1Messenger));
            vm.mockCall(
                address(l1t1Messenger),
                abi.encodeWithSignature("xDomainMessageSender()"),
                abi.encode(address(destinationReader))
            );

            originReader.handle(destination, TypeCasts.addressToBytes32(address(destinationReader)), message);
            vm.stopPrank();
        }

        // Verify the order status was correctly read
        // bool orderFilled = abi.decode(l1_t1_7683_pull_based.lastResult(), (bool));
        // assertTrue(orderFilled);
    }

    // 1. user opens intent on source chain
    // 2. solver fills intent on destination chain
    // 3a. solver calls 7683 verifySettlement on source chain which T1XChainRead.requestRead
    // 3b. relayer picks up message and calls relayMessage on destination chain
    // 3c. relayMessage calls T1XChainRead.handle which calls the view function, and packages the result into
    // sendMessage
    // 4a. relayer picks up message and calls relayMessageWithProof on source chain
    // 4b. relayMessageWithProof calls T1XChainRead.handle which calls _handleReadResponse which calls
    // onT1XChainReadResult on callback address
    // 4c. onT1XChainReadResult on 7683 contract settles intent and releases funds to solver
    function test_pullBasedSettlementFlow() public {
        // 1. Setup: Open an order on L1 (origin chain)
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1_t1_7683_pull_based), amount);
        vm.recordLogs();
        l1_t1_7683_pull_based.open(order);
        vm.stopPrank();

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();
        assertEq(l1_t1_7683_pull_based.orderStatus(orderId), _base7683.OPENED());

        // 2. Fill the order on L2 (destination chain)
        vm.startPrank(vegeta);
        outputToken.approve(address(l2_t1_7683_pull_based), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        l2_t1_7683_pull_based.fill(orderId, originData, fillerData);
        assertEq(l2_t1_7683_pull_based.orderStatus(orderId), l2_t1_7683_pull_based.FILLED());
        vm.stopPrank();

        // 3. Filler initiates settlement verification from L1
        vm.startPrank(vegeta);
        bytes32 requestId = l1_t1_7683_pull_based.verifySettlement(destination, address(l2_t1_7683_pull_based), orderId);
        vm.stopPrank();

        // 4. Process the read request on L2 (destination chain)
        {
            // Construct the read request calldata
            bytes memory callData = abi.encodeWithSelector(l2_t1_7683_pull_based.getFilledOrderStatus.selector, orderId);
            bytes memory readMessage = T1Message.encodeRead(requestId, address(l2_t1_7683_pull_based), callData);
            bytes memory handleMessage = abi.encodeWithSelector(destinationReader.handle.selector, origin, TypeCasts.addressToBytes32(address(originReader)), readMessage);
            l2t1Messenger.relayMessage(vegeta, address(destinationReader), 0, 0, handleMessage);
        }

        // 5. Relay the result back to L1 using relayMessage
        {
            // Get the result (FILLED status)
            bytes memory result = l2_t1_7683_pull_based.getFilledOrderStatus(orderId);
            bytes memory resultMessage = T1Message.encodeReadResult(requestId, result);

            bytes memory outerMessage = abi.encodeWithSelector(
                T1XChainRead.handle.selector,
                destination,
                TypeCasts.addressToBytes32(address(destinationReader)),
                resultMessage
            );

            // Calculate message hash
            bytes32 xDomainCalldataHash = keccak256(
                abi.encodeWithSignature(
                    "relayMessage(address,address,uint256,uint256,bytes)",
                    address(destinationReader),
                    address(originReader),
                    0,
                    0, // First nonce
                    outerMessage
                )
            );

            // Append message to L2 message queue
            vm.startPrank(address(l2t1Messenger));
            l2MessageQueue.appendMessage(xDomainCalldataHash);
            vm.stopPrank();

            // Simulate batch finalization
            bytes memory batchHeader = generateBatchHeader();
            rollup.addProver(address(0));
            vm.startPrank(address(0));
            rollup.finalizeBundleWithProof(batchHeader, bytes32(uint256(2)), xDomainCalldataHash, new bytes(0));
            vm.stopPrank();

            // Relay message from L2 to L1
            IL1T1Messenger.L2MessageProof memory proof = IL1T1Messenger.L2MessageProof({
                batchIndex: 1,
                merkleProof: new bytes(0) // Mock proof
             });

            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

            l1t1Messenger.relayMessageWithProof(
                address(destinationReader), address(originReader), 0, 0, outerMessage, proof
            );

            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // 6. Verify the final state on L1
        assertTrue(l1_t1_7683_pull_based.orderVerified(orderId), "Order should be verified");
    }
}

// Helper library for the tests
library T1Message {
    function encodeRead(bytes32 requestId, address tc, bytes memory callData) internal pure returns (bytes memory) {
        return abi.encode(true, requestId, abi.encode(tc, callData));
    }

    function encodeReadResult(bytes32 requestId, bytes memory result) internal pure returns (bytes memory) {
        return abi.encode(false, requestId, result);
    }
}
