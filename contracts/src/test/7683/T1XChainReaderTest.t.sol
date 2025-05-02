// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "intents-framework/ERC7683/IERC7683.sol";

import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { BaseT1XChainReader } from "../../libraries/xChain/BaseT1XChainReader.sol";
import { T1BasicSwapE2E } from "./T1BasicSwapE2E.t.sol";
import { T1ERC7683Pull } from "../../7683/T1ERC7683Pull.sol";

contract T1XChainReaderTest is T1BasicSwapE2E {
    using TypeCasts for address;

    T1XChainReader internal originReader;
    T1XChainReader internal destinationReader;
    T1ERC7683Pull internal L1T17683Pull;
    T1ERC7683Pull internal L2T17683Pull;

    function setUp() public virtual override {
        super.setUp();

        // Deploy T1XChainReader on both chains
        originReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(originReader)),
            address(new T1XChainReader(address(l1t1Messenger), address(this), origin))
        );

        destinationReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)),
            address(new T1XChainReader(address(l2t1Messenger), address(this), destination))
        );

        L1T17683Pull = T1ERC7683Pull(payable(_deployProxy(address(0))));
        L2T17683Pull = T1ERC7683Pull(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(L1T17683Pull)),
            address(new T1ERC7683Pull(address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(L2T17683Pull)),
            address(new T1ERC7683Pull(address(0), address(destinationReader), uint32(destination)))
        );
        L1T17683Pull.initialize(address(L2T17683Pull));
        L2T17683Pull.initialize(address(L1T17683Pull));
    }

    // 1. user opens intent on source chain
    // 2. solver fills intent on destination chain
    // 3a. solver calls 7683 verifySettlement on source chain, triggering T1XChainReader.requestRead
    // 4a. relayer picks up message and calls getFilledOrderStatus on destination chain
    // 4b. relayer calls T1XChainReader.handle with the result of the read which calls
    // onT1XChainReaderResult on callback address
    // 4c. onT1XChainReaderResult on 7683 contract settles intent and releases funds to solver
    function test_ERC7683PullSettlementFlow() public {
        // 1. Setup: Open an order on L1 (origin chain)
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(L1T17683Pull), amount);
        vm.recordLogs();
        L1T17683Pull.open(order);
        vm.stopPrank();

        (bytes32 orderId,) = _getOrderIDFromLogs();
        assertEq(L1T17683Pull.orderStatus(orderId), _base7683.OPENED());

        // 2. Fill the order on L2 (destination chain)
        vm.startPrank(vegeta);
        outputToken.approve(address(L2T17683Pull), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        L2T17683Pull.fill(orderId, originData, fillerData);
        assertEq(L2T17683Pull.orderStatus(orderId), L2T17683Pull.FILLED());
        vm.stopPrank();

        // 3. Filler initiates settlement verification from L1
        vm.startPrank(vegeta);
        bytes32 requestId = L1T17683Pull.verifySettlement(destination, orderId);
        vm.stopPrank();

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory orderStatus = L2T17683Pull.getFilledOrderStatus(orderId);
            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            originReader.handle(destination, destinationRouterB32, requestId, orderStatus);
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertTrue(L1T17683Pull.orderVerified(orderId), "Order should be verified");
    }

    function test_onlyProver_revert() public {
        bytes32 requestId = hex"";
        bytes memory orderStatus = hex"";

        vm.prank(address(0xbeef));
        vm.expectRevert(BaseT1XChainReader.OnlyProver.selector);
        originReader.handle(destination, destinationRouterB32, requestId, orderStatus);

    }
}
