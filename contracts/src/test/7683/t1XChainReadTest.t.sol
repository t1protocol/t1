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

import { T1XChainRead, IT1XChainReadCallback } from "../../libraries/x-chain/T1XChainRead.sol";
import { t1BasicSwapE2E } from "./t1BasicSwapE2E.t.sol";
import { IL1T1Messenger } from "../../L1/IL1T1Messenger.sol";
import { L1T1Messenger } from "../../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../../L2/L2T1Messenger.sol";
import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";

contract TargetContract {
    uint256 public value;
    mapping(bytes32 => bool) public orders;

    function getOrderStatus(bytes32 _orderId) external view returns (bool) {
        return orders[_orderId];
    }

    constructor(uint256 _value) {
        value = _value;
    }

    function getValue() external view returns (uint256) {
        return value;
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
    T1XChainRead internal originReader;
    T1XChainRead internal destinationReader;
    TargetContract internal tc;
    CallbackContract internal callbackContract;

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
    }

    function test_crossChainRead_getValue() public {
        // Create the calldata for reading the value
        bytes memory callData = abi.encodeWithSelector(TargetContract.getValue.selector);

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
                abi.encodeWithSelector(L2T1Messenger.getXDomainMessageSender.selector),
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
                abi.encodeWithSelector(L1T1Messenger.getXDomainMessageSender.selector),
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
                abi.encodeWithSelector(L2T1Messenger.getXDomainMessageSender.selector),
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
                abi.encodeWithSelector(L1T1Messenger.getXDomainMessageSender.selector),
                abi.encode(address(destinationReader))
            );

            originReader.handle(destination, TypeCasts.addressToBytes32(address(destinationReader)), message);
            vm.stopPrank();
        }

        // Verify the order status was correctly read
        bool orderFilled = abi.decode(callbackContract.lastResult(), (bool));
        assertTrue(orderFilled);
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
