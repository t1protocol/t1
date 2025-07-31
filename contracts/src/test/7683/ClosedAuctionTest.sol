// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { IT1XChainReader } from "../../libraries/xChain/IT1XChainReader.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { Base7683 } from "../../7683/Base7683.sol";

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
        l1T1ERC7683.commitWinnerBid(orderId, T1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount }));

        (address actualSettlementReceiver, uint256 actualAmountOut) = l1T1ERC7683.orderToBid(orderId);
        assertEq(actualSettlementReceiver, vegeta);
        assertEq(actualAmountOut, amount);

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
        );

        assertTrue(l1T1ERC7683.orderVerified(orderId), "Order should be verified");

        (actualSettlementReceiver, actualAmountOut) = l1T1ERC7683.orderToBid(orderId);
        assertEq(actualSettlementReceiver, address(0));
        assertEq(actualAmountOut, 0);
    }

    function test_revertIfWinnerBidNotCommited() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);

        vm.expectRevert(abi.encodeWithSelector(T1ERC7683.InvalidFill.selector, vegeta, address(0), amount, 0));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidReceiver() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, T1ERC7683.Bid({ settlementReceiver: kakaroto, amountOut: amount }));

        vm.expectRevert(abi.encodeWithSelector(T1ERC7683.InvalidFill.selector, vegeta, kakaroto, amount, amount));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidAmountOut() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, T1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount * 2 }));

        vm.expectRevert(abi.encodeWithSelector(T1ERC7683.InvalidFill.selector, vegeta, vegeta, amount, amount * 2));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertIfInvalidBid() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.commitWinnerBid(orderId, T1ERC7683.Bid({ settlementReceiver: kakaroto, amountOut: amount * 2 }));

        vm.expectRevert(abi.encodeWithSelector(T1ERC7683.InvalidFill.selector, vegeta, kakaroto, amount, amount * 2));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_revertCommitIfNotOwner() public {
        (, bytes32 orderId,) = _openAndFillOrder();

        vm.prank(vegeta);
        vm.expectRevert();
        l1T1ERC7683.commitWinnerBid(orderId, T1ERC7683.Bid({ settlementReceiver: vegeta, amountOut: amount }));
    }

    function _openAndFillOrder() internal returns (OrderData memory, bytes32 orderId, bytes32 requestId) {
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
        assertEq(l1T1ERC7683.orderStatus(orderId_), l1T1ERC7683.OPENED());

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        assertEq(l2T1ERC7683.orderStatus(orderId_), l2T1ERC7683.FILLED());
        vm.stopPrank();

        vm.startPrank(vegeta);
        bytes32 requestId_ = l1T1ERC7683.verifySettlement(destination, orderId_);
        vm.stopPrank();

        return (orderData, orderId_, requestId_);
    }

    /// @dev Generate a merkle tree with depth 2 (4 leaves) including the result value and a proof
    /// @param requestId Proof of read request id
    /// @param result Result of the read
    /// @param position position of the leaf where result is stored (0-3)
    /// @return root Root of the merkle tree
    /// @return proof Proof of for the leaf where result is stored
    function _generateMerkleTree(
        bytes32 requestId,
        bytes memory result,
        uint256 position
    )
        private
        pure
        returns (bytes32 root, bytes memory proof)
    {
        require(position < 4, "position must be < 4 for depth 2 tree");

        // Generate 4 leaves, one for the result and three for the mock leaves
        bytes32[] memory leafs = new bytes32[](4);
        for (uint256 i = 0; i < leafs.length; i++) {
            if (i == position) {
                bytes32 xChainReadResultHash = keccak256(result);
                // Use abi.encodePacked to match T1ERC7683.sol line 138
                leafs[i] = keccak256(abi.encodePacked(xChainReadResultHash, requestId));
            } else {
                bytes32 mockLeaf = keccak256(abi.encodePacked("mock_leaf", i));
                leafs[i] = mockLeaf;
            }
        }

        // Build intermediate nodes
        bytes32[] memory level1 = new bytes32[](2);
        level1[0] = _efficientHash(leafs[0], leafs[1]);
        level1[1] = _efficientHash(leafs[2], leafs[3]);

        root = _efficientHash(level1[0], level1[1]);

        // Generate proof for the target leaf at position position
        bytes32[] memory proofElements = new bytes32[](2);
        uint256 currentposition = position;

        // Leaf sibling
        if (currentposition % 2 == 0) {
            proofElements[0] = leafs[currentposition + 1];
        } else {
            proofElements[0] = leafs[currentposition - 1];
        }
        currentposition /= 2;

        // Intermediate node sibling
        if (currentposition % 2 == 0) {
            proofElements[1] = level1[currentposition + 1];
        } else {
            proofElements[1] = level1[currentposition - 1];
        }

        // Encode proof as concatenated bytes32 values (WithdrawTrieVerifier expects this format)
        proof = new bytes(64); // 2 * 32 bytes
        assembly {
            mstore(add(proof, 0x20), mload(add(proofElements, 0x20)))
            mstore(add(proof, 0x40), mload(add(proofElements, 0x40)))
        }
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
