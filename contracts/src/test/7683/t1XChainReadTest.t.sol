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

import { T1XChainRead } from "../../libraries/x-chain/T1XChainRead.sol";
import { IT1XChainReadCallback } from "../../libraries/x-chain/IT1XChainReadCallback.sol";
import { T1Message } from "../../libraries/x-chain/T1Message.sol";
import { t1BasicSwapE2E } from "./t1BasicSwapE2E.t.sol";
import { IL1T1Messenger } from "../../L1/IL1T1Messenger.sol";
import { L1T1Messenger } from "../../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../../L2/L2T1Messenger.sol";
import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";
import { t1_7683_PullBased } from "../../7683/t1_7683_pull_based.sol";

contract T1XChainReadTest is t1BasicSwapE2E {
    using TypeCasts for address;

    T1XChainRead internal originReader;
    T1XChainRead internal destinationReader;
    t1_7683_PullBased internal l1_t1_7683_pull_based;
    t1_7683_PullBased internal l2_t1_7683_pull_based;

    function setUp() public virtual override {
        super.setUp();

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

        (bytes32 orderId,) = _getOrderIDFromLogs();
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
            bytes memory handleMessage = abi.encodeWithSelector(
                destinationReader.handle.selector,
                origin,
                TypeCasts.addressToBytes32(address(originReader)),
                readMessage
            );
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
