// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { StandardHookMetadata } from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import { MockMailbox } from "@hyperlane-xyz/mock/MockMailbox.sol";
import { MockHyperlaneEnvironment } from "@hyperlane-xyz/mock/MockHyperlaneEnvironment.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPostDispatchHook } from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";

import { BaseTest, TestInterchainGasPaymaster } from "./BaseTest.sol";
import { Base7683 } from "intents-framework/Base7683.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "intents-framework/ERC7683/IERC7683.sol";

import { t1_7683 } from "../../7683/t1_7683.sol";
import { L1MessageQueue } from "../../L1/rollup/L1MessageQueue.sol";
import { IL1MessageQueue } from "../../L1/rollup/IL1MessageQueue.sol";
import { L2MessageQueue } from "../../L2/predeploys/L2MessageQueue.sol";
import { IL1MessageQueueWithGasPriceOracle } from "../../L1/rollup/IL1MessageQueueWithGasPriceOracle.sol";
import { L1T1Messenger } from "../../L1/L1T1Messenger.sol";
import { IL1T1Messenger } from "../../L1/IL1T1Messenger.sol";
import { L2T1Messenger } from "../../L2/L2T1Messenger.sol";
import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";
import { MockRollupVerifier } from "../mocks/MockRollupVerifier.sol";

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Refunded(bytes32 orderId, address receiver);

contract t1BasicSwapE2E is BaseTest {
    using TypeCasts for address;

    L1T1Messenger internal l1t1Messenger;
    L2T1Messenger internal l2t1Messenger;
    L1MessageQueue internal messageQueue;
    L2MessageQueue internal l2MessageQueue;
    T1ChainMockBlob internal rollup;
    MockRollupVerifier internal verifier;

    TestInterchainGasPaymaster internal igp;

    t1_7683 internal originRouter;
    t1_7683 internal destinationRouter;

    bytes32 internal originRouterB32;
    bytes32 internal destinationRouterB32;
    bytes32 internal destinationRouterOverrideB32;

    uint256 gasPaymentQuote;
    uint256 gasPaymentQuoteOverride;
    uint256 internal constant GAS_LIMIT = 60_000;

    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");
    address internal feeVault;

    function _deployProxiedOriginRouter(L1T1Messenger _messenger, address _owner) internal returns (t1_7683) {
        t1_7683 implementation = new t1_7683(address(_messenger), permit2, origin);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            abi.encodeWithSelector(t1_7683.initialize.selector, address(0), address(0), _owner)
        );

        return t1_7683(address(proxy));
    }

    function _deployProxiedDestinationRouter(
        L2T1Messenger _messenger,
        address _counterpart
    )
        internal
        returns (t1_7683)
    {
        t1_7683 implementation = new t1_7683(address(_messenger), permit2, destination);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation), address(admin), abi.encodeWithSelector(t1_7683.initialize.selector, _counterpart)
        );

        return t1_7683(address(proxy));
    }

    function labelAccounts() internal {
        vm.label(owner, "Owner");
        vm.label(sender, "Sender");
        vm.label(feeVault, "Fee Vault");
        vm.label(kakaroto, "Kakaroto");
        vm.label(vegeta, "Vegeta");
        vm.label(karpincho, "Karpincho");
        vm.label(address(l1t1Messenger), "l1t1Messenger");
        vm.label(address(l2t1Messenger), "l2t1Messenger");
        vm.label(address(rollup), "rollup");
        vm.label(address(messageQueue), "messageQueue");
        vm.label(address(l2MessageQueue), "l2MessageQueue");
        vm.label(address(originRouter), "originRouter");
        vm.label(address(destinationRouter), "destinationRouter");
    }

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();
        onSetup();
    }

    function onSetup() public {
        l1t1Messenger = L1T1Messenger(payable(_deployProxy(address(0))));
        rollup = T1ChainMockBlob(_deployProxy(address(0)));
        messageQueue = L1MessageQueue(_deployProxy(address(0)));
        admin.upgrade(ITransparentUpgradeableProxy(address(messageQueue)), address(new L1MessageQueue()));
        uint256 maxGasLimit = 5_000_000;
        messageQueue.initialize(address(0), maxGasLimit);
        l2MessageQueue = new L2MessageQueue(address(this));
        l2t1Messenger = L2T1Messenger(payable(_deployProxy(address(0))));

        verifier = new MockRollupVerifier();

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2t1Messenger)),
            address(new L2T1Messenger(address(l1t1Messenger), address(l2MessageQueue)))
        );
        l2MessageQueue.initialize(address(l2t1Messenger));

        uint64[] memory network = new uint64[](1);
        network[0] = origin;
        l2t1Messenger.initialize(address(l1t1Messenger), network);

        feeVault = address(uint160(address(this)) - 1);

        // Upgrade the L1T1Messenger implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1t1Messenger)),
            address(new L1T1Messenger(address(l2t1Messenger), address(rollup), address(messageQueue)))
        );
        l1t1Messenger.initialize(feeVault);

        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new T1ChainMockBlob(1233, address(messageQueue), address(verifier)))
        );
        rollup.initialize(44);

        igp = new TestInterchainGasPaymaster();

        gasPaymentQuote = igp.quoteGasPayment(destination, GAS_LIMIT);

        originRouter = _deployProxiedOriginRouter(l1t1Messenger, owner);

        _base7683 = Base7683(address(originRouter));

        destinationRouter = _deployProxiedDestinationRouter(l2t1Messenger, address(originRouter));

        originRouterB32 = TypeCasts.addressToBytes32(address(originRouter));
        destinationRouterB32 = TypeCasts.addressToBytes32(address(destinationRouter));

        balanceId[address(originRouter)] = 4;
        balanceId[address(destinationRouter)] = 5;
        balanceId[address(igp)] = 6;

        users.push(address(originRouter));
        users.push(address(destinationRouter));
        users.push(address(igp));

        vm.stopPrank();

        labelAccounts();
    }

    receive() external payable { }

    function _prepareOrderData() internal view returns (OrderData memory) {
        return OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(karpincho),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            amountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: address(destinationRouter).addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
        });
    }

    function _prepareGaslessOrder(
        bytes memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline
    )
        internal
        view
        returns (GaslessCrossChainOrder memory)
    {
        return _prepareGaslessOrder(
            address(originRouter),
            kakaroto,
            uint64(origin),
            orderData,
            permitNonce,
            openDeadline,
            fillDeadline,
            OrderEncoder.orderDataType()
        );
    }

    function test_open_fill_settle() public {
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

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances(outputToken);

        assertEq(
            balancesAfterFill[balanceId[vegeta]],
            balancesBeforeFill[balanceId[vegeta]] - amount,
            "vegeta balance after fill"
        );
        assertEq(
            balancesAfterFill[balanceId[karpincho]],
            balancesBeforeFill[balanceId[karpincho]] + amount,
            "karpincho balance after fill"
        );

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances(inputToken);
        handleRelayMessage(orderIds, ordersFillerData, true);

        uint256[] memory balancesAfterSettle = _balances(inputToken);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(
            balancesAfterSettle[balanceId[vegeta]],
            balancesBeforeSettle[balanceId[vegeta]] + amount,
            "vegeta balance after settle"
        );
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount,
            "originRouter balance after fill"
        );
    }

    function test_native_open_fill_settle() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.open{ value: amount }(order);

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
            address(0),
            address(0)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto, true);

        // fill
        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeFill = _balances();

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Filled(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        destinationRouter.fill{ value: amount }(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = destinationRouter.filledOrders(orderId);

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances();

        assertEq(balancesAfterFill[balanceId[vegeta]], balancesBeforeFill[balanceId[vegeta]] - amount);
        assertEq(balancesAfterFill[balanceId[karpincho]], balancesBeforeFill[balanceId[karpincho]] + amount);

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances();

        handleRelayMessage(orderIds, ordersFillerData, true);

        uint256[] memory balancesAfterSettle = _balances();

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(balancesAfterSettle[balanceId[vegeta]], balancesBeforeSettle[balanceId[vegeta]] + amount);
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount
        );
    }

    function test_openFor_fill_settle() public {
        // open
        uint256 permitNonce = 0;
        OrderData memory orderData = _prepareOrderData();

        uint32 openDeadline = uint32(block.timestamp + 10);

        GaslessCrossChainOrder memory order =
            _prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, openDeadline, orderData.fillDeadline);

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        bytes32 witness = originRouter.witnessHash(originRouter.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(originRouter), witness, address(inputToken), permitNonce, amount, openDeadline, kakarotoPK
        );

        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            openDeadline,
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

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances(outputToken);

        assertEq(balancesAfterFill[balanceId[vegeta]], balancesBeforeFill[balanceId[vegeta]] - amount);
        assertEq(balancesAfterFill[balanceId[karpincho]], balancesBeforeFill[balanceId[karpincho]] + amount);

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances(inputToken);

        handleRelayMessage(orderIds, ordersFillerData, true);

        uint256[] memory balancesAfterSettle = _balances(inputToken);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(balancesAfterSettle[balanceId[vegeta]], balancesBeforeSettle[balanceId[vegeta]] + amount);
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount
        );
    }

    function test_open_refund() public {
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

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        vm.stopPrank();

        bytes[] memory emptyOrdersFillerData = new bytes[](1);
        emptyOrdersFillerData[0] = hex"";

        handleRelayMessage(orderIds, emptyOrdersFillerData, false);

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }

    function test_native_open_refund() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.open{ value: amount }(order);

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
            address(0),
            address(0)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto, true);

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund(orders);

        vm.stopPrank();

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances();

        bytes[] memory emptyOrdersFillerData = new bytes[](1);
        emptyOrdersFillerData[0] = hex"";

        handleRelayMessage(orderIds, emptyOrdersFillerData, false);

        uint256[] memory balancesAfterRefund = _balances();

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }

    function test_openFor_refund() public {
        // open
        uint256 permitNonce = 0;
        OrderData memory orderData = _prepareOrderData();

        uint32 openDeadline = uint32(block.timestamp + 10);

        GaslessCrossChainOrder memory order =
            _prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, openDeadline, orderData.fillDeadline);

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        bytes32 witness = originRouter.witnessHash(originRouter.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(originRouter), witness, address(inputToken), permitNonce, amount, openDeadline, kakarotoPK
        );

        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            openDeadline,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund(orders);

        vm.stopPrank();

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        bytes[] memory emptyOrdersFillerData = new bytes[](1);
        emptyOrdersFillerData[0] = hex"";

        handleRelayMessage(orderIds, emptyOrdersFillerData, false);

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }

    function handleRelayMessage(bytes32[] memory orderIds, bytes[] memory ordersFillerData, bool isSettle) internal {
        rollup.addProver(address(0));
        bytes memory batchHeader1 = generateBatchHeader();
        assertEq(rollup.isBatchFinalized(1), false);

        bytes memory innerMessage = abi.encode(isSettle, orderIds, ordersFillerData);

        bytes memory outerMessage = abi.encodeWithSelector(
            t1_7683.handle.selector, origin, TypeCasts.addressToBytes32(address(destinationRouter)), innerMessage
        );

        // hash 0xcca132db240c06c148d210ceda18701a38e863e5ab2ed4638b15b6c7b30a08ae
        uint256 nonce = 0;
        uint256 msgValue = 0;
        address from = address(destinationRouter);
        address to = address(originRouter);

        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)", from, to, msgValue, nonce, outerMessage
        );

        bytes32 withdrawRoot = keccak256(xDomainCalldata);
        vm.startPrank(address(0));
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(uint256(2)), withdrawRoot, new bytes(0));

        vm.stopPrank();
        assertEq(rollup.isBatchFinalized(1), true);

        bytes32 withdrawRootBatch1 = rollup.withdrawRoots(1);
        assertEq(withdrawRoot, withdrawRootBatch1, "withdraw root");

        bytes memory proof = hex"";
        IL1T1Messenger.L2MessageProof memory messageProof =
            IL1T1Messenger.L2MessageProof({ batchIndex: 1, merkleProof: proof });
        l1t1Messenger.relayMessageWithProof(from, to, msgValue, nonce, outerMessage, messageProof);
    }

    function generateBatchHeader() internal view returns (bytes memory batchHeader1) {
        batchHeader1 = new bytes(193);
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory blobDataProof =
        // solhint-disable-next-line max-line-length
            hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        assembly {
            mstore8(add(batchHeader1, 0x20), 3) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            // dataHash
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51)
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), 0) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        batchHeader1[1] = bytes1(uint8(0)); // change back
    }
}
