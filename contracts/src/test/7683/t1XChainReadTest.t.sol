// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "intents-framework/ERC7683/IERC7683.sol";

import { t1XChainReader } from "../../libraries/xChain/t1XChainReader.sol";
import { T1Message } from "../../libraries/xChain/T1Message.sol";
import { t1BasicSwapE2E } from "./t1BasicSwapE2E.t.sol";
import { t1ERC7683Pull } from "../../7683/t1ERC7683Pull.sol";

contract t1XChainReaderTest is t1BasicSwapE2E {
    using TypeCasts for address;

    t1XChainReader internal originReader;
    t1XChainReader internal destinationReader;
    t1ERC7683Pull internal l1_t1_7683_pull;
    t1ERC7683Pull internal l2_t1_7683_pull;

    function setUp() public virtual override {
        super.setUp();

        // Deploy t1XChainReader on both chains
        originReader = t1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(originReader)),
            address(new t1XChainReader(address(l1t1Messenger), origin))
        );

        destinationReader = t1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)),
            address(new t1XChainReader(address(l2t1Messenger), destination))
        );

        l1_t1_7683_pull = t1ERC7683Pull(payable(_deployProxy(address(0))));
        l2_t1_7683_pull = t1ERC7683Pull(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1_t1_7683_pull)),
            address(new t1ERC7683Pull(address(l1t1Messenger), address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2_t1_7683_pull)),
            address(
                new t1ERC7683Pull(address(l2t1Messenger), address(0), address(destinationReader), uint32(destination))
            )
        );
        l1_t1_7683_pull.initialize(address(l2_t1_7683_pull));
        l2_t1_7683_pull.initialize(address(l1_t1_7683_pull));
    }

    // 1. user opens intent on source chain
    // 2. solver fills intent on destination chain
    // 3a. solver calls 7683 verifySettlement on source chain, triggering t1XChainReader.requestRead
    // 4a. relayer picks up message and calls getFilledOrderStatus on destination chain
    // 4b. relayer calls t1XChainReader.handle with the result of the read which calls
    // ont1XChainReaderResult on callback address
    // 4c. ont1XChainReaderResult on 7683 contract settles intent and releases funds to solver
    function test_pullBasedSettlementFlow() public {
        // 1. Setup: Open an order on L1 (origin chain)
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1_t1_7683_pull), amount);
        vm.recordLogs();
        l1_t1_7683_pull.open(order);
        vm.stopPrank();

        (bytes32 orderId,) = _getOrderIDFromLogs();
        assertEq(l1_t1_7683_pull.orderStatus(orderId), _base7683.OPENED());

        // 2. Fill the order on L2 (destination chain)
        vm.startPrank(vegeta);
        outputToken.approve(address(l2_t1_7683_pull), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        l2_t1_7683_pull.fill(orderId, originData, fillerData);
        assertEq(l2_t1_7683_pull.orderStatus(orderId), l2_t1_7683_pull.FILLED());
        vm.stopPrank();

        // 3. Filler initiates settlement verification from L1
        vm.startPrank(vegeta);
        bytes32 requestId = l1_t1_7683_pull.verifySettlement(destination, orderId);
        vm.stopPrank();

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory orderStatus = l2_t1_7683_pull.getFilledOrderStatus(orderId);
            bytes memory readMessage = T1Message.encodeRead(requestId, orderStatus);
            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            vm.prank(address(l1t1Messenger));
            originReader.handle(readMessage);
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertTrue(l1_t1_7683_pull.orderVerified(orderId), "Order should be verified");
    }
}
