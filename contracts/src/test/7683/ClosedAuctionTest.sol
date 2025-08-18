// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { IT1XChainReader } from "../../libraries/xChain/IT1XChainReader.sol";
import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";

contract ClosedAuctionTest is T1XChainReaderBaseTestSetup {
    using TypeCasts for address;

    uint256 batchIndex = 0;
    uint256 position = 0;

    function setUp() public virtual override {
        super.setUp();

        // Deploy T1XChainReader on both chains
        originReader = T1XChainReader(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(ITransparentUpgradeableProxy(address(originReader)), address(new T1XChainReader(address(this))));
        originReader.initialize(address(this));

        destinationReader = T1XChainReader(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)), address(new T1XChainReader(address(this)))
        );
        destinationReader.initialize(address(this));

        l1T1ERC7683 = T1ERC7683(payable(_deployProxy(address(proxyOwner))));
        l2T1ERC7683 = T1ERC7683(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1T1ERC7683)),
            address(new T1ERC7683(address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2T1ERC7683)),
            address(new T1ERC7683(address(0), address(destinationReader), uint32(destination)))
        );
        l1T1ERC7683.initialize(address(l2T1ERC7683));
        l2T1ERC7683.initialize(address(l1T1ERC7683));
    }

    function test_settleWithCorrectBid() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, IT1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount }));

        (address actualSettlementReceiver, uint256 actualAmountOut) = l1T1ERC7683.orderToBid(orderId);
        assertEq(actualSettlementReceiver, vegeta);
        assertEq(actualAmountOut, amount);

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
        );

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");

        (actualSettlementReceiver, actualAmountOut) = l1T1ERC7683.orderToBid(orderId);
        assertEq(actualSettlementReceiver, address(0));
        assertEq(actualAmountOut, 0);
    }

    function test_revertIfWinnerBidNotCommited() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);

        vm.expectRevert(abi.encodeWithSelector(IT1ERC7683.InvalidFill.selector, vegeta, address(0), amount, 0));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidReceiver() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, IT1ERC7683.Bid({ settlementReceiver: kakaroto, amountOut: amount }));

        vm.expectRevert(abi.encodeWithSelector(IT1ERC7683.InvalidFill.selector, vegeta, kakaroto, amount, amount));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidAmountOut() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, IT1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount * 2 }));

        vm.expectRevert(abi.encodeWithSelector(IT1ERC7683.InvalidFill.selector, vegeta, vegeta, amount, amount * 2));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidBid() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, IT1ERC7683.Bid({ settlementReceiver: kakaroto, amountOut: amount * 2 }));

        vm.expectRevert(abi.encodeWithSelector(IT1ERC7683.InvalidFill.selector, vegeta, kakaroto, amount, amount * 2));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertCommitIfNotOwner() public {
        (, bytes32 orderId,) = _openAndFillOrder();

        vm.prank(vegeta);
        vm.expectRevert();
        l1T1ERC7683.commitWinnerBid(orderId, IT1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount }));
    }

    function _openAndFillOrder() internal override returns (OrderData memory, bytes32 orderId, bytes32 requestId) {
        OrderData memory orderData = _prepareOrderData();
        orderData.closedAuction = true;
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId_)), uint8(IT1ERC7683.Status.OPENED));

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        assertEq(uint8(l2T1ERC7683.orderStatus(orderId_)), uint8(IT1ERC7683.Status.FILLED));
        vm.stopPrank();

        vm.startPrank(vegeta);
        bytes32 requestId_ = l1T1ERC7683.verifySettlement(destination, orderId_);
        vm.stopPrank();

        return (orderData, orderId_, requestId_);
    }
}
