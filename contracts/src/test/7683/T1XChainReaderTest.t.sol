// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "intents-framework/ERC7683/IERC7683.sol";

import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1BasicSwapE2E } from "./T1BasicSwapE2E.t.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";

contract T1XChainReaderTest is T1BasicSwapE2E {
    using TypeCasts for address;

    T1XChainReader internal originReader;
    T1XChainReader internal destinationReader;
    T1ERC7683 internal L1T17683;
    T1ERC7683 internal L2T17683;

    function setUp() public virtual override {
        super.setUp();

        // Deploy T1XChainReader on both chains
        originReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(originReader)),
            address(new T1XChainReader(address(l1t1Messenger), address(this)))
        );

        destinationReader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)),
            address(new T1XChainReader(address(l2t1Messenger), address(this)))
        );

        L1T17683 = T1ERC7683(payable(_deployProxy(address(0))));
        L2T17683 = T1ERC7683(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(L1T17683)),
            address(new T1ERC7683(address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(L2T17683)),
            address(new T1ERC7683(address(0), address(destinationReader), uint32(destination)))
        );
        L1T17683.initialize(address(L2T17683));
        L2T17683.initialize(address(L1T17683));
    }

    // 1. user opens intent on source chain
    // 2. solver fills intent on destination chain
    // 3a. solver calls 7683 verifySettlement on source chain, triggering T1XChainReader.requestRead
    // 4a. relayer picks up message and calls getFilledOrderStatus on destination chain
    // 4b. relayer calls T1XChainReader.commitProofOfReadRoot with the merkle proof containing the result of the read
    // that
    // writes the new merkle root for the target batch
    // 5. Solver calls handleReadResultWithProof on 7683 contract with merkle proof, settles intent and releases funds
    function test_ERC7683SettlementFlow() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory result = L2T17683.getFilledOrderStatus(orderId);

            // Generate merkle tree and proof for the result
            (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            originReader.commitProofOfReadRoot(batchIndex, root);
            L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertTrue(L1T17683.orderVerified(orderId), "Order should be verified");
    }

    function test_ERC7683SettlementFlowWithAnotherTreePosition() public {
        uint256 batchIndex = 0;
        uint256 position = 3;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory result = L2T17683.getFilledOrderStatus(orderId);
            // Generate merkle tree and proof for the result
            (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            originReader.commitProofOfReadRoot(batchIndex, root);
            L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertTrue(L1T17683.orderVerified(orderId), "Order should be verified");
    }

    function test_incrementBatchIndex() public {
        uint256 batchIndex = 0;
        bytes32 root = bytes32(vm.randomBytes(32));

        uint256 precommitBatchIndex = originReader.nextBatchIndex();
        originReader.commitProofOfReadRoot(batchIndex, root);
        uint256 postcommitBatchIndex = originReader.nextBatchIndex();

        assertEq(precommitBatchIndex + 1, postcommitBatchIndex, "Batch index should be incremented");
    }

    function test_proverAbleToUpdatePreviousBatchIndexRoot() public {
        uint256 batchIndex = 0;
        bytes32 root = bytes32(vm.randomBytes(32));
        bytes32 root2 = bytes32(vm.randomBytes(32));

        originReader.commitProofOfReadRoot(batchIndex, root);
        originReader.commitProofOfReadRoot(batchIndex, root2);

        assertEq(originReader.proofOfReadRoots(batchIndex), root2, "Root should be updated");
    }

    function test_revertWithInvalidProofData() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        bytes memory result = L2T17683.getFilledOrderStatus(orderId);
        (bytes32 root,) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        bytes memory invalidProof = hex"11";

        vm.expectRevert("Invalid proof");
        L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, invalidProof));
    }

    function test_revertWithInvalidProof() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        bytes memory result = L2T17683.getFilledOrderStatus(orderId);
        (bytes32 root,) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Use an invalid proof that is the correct length (64 bytes) but contains wrong data
        bytes memory invalidProof = abi.encodePacked(
            bytes32(0x1111111111111111111111111111111111111111111111111111111111111111),
            bytes32(0x2222222222222222222222222222222222222222222222222222222222222222)
        );

        vm.expectRevert(T1XChainReader.InvalidProof.selector);
        L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, invalidProof));
    }

    function test_revertWithInvalidResultData() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (,, bytes32 requestId) = _openAndFillOrder();

        // 4. First, set up the proof root by calling handle on the reader

        // Construct read request calldata
        bytes memory result = hex"11";
        // Generate merkle tree and proof for the result
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        // Set up the proof root in the T1ERC7683 contract
        originReader.commitProofOfReadRoot(batchIndex, root);

        // 5. Now test handleReadResultWithProof with invalid result data
        vm.expectRevert();
        L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_SameProofShouldNotSettleTwice() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        {
            bytes memory result = L2T17683.getFilledOrderStatus(orderId);
            (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

            originReader.commitProofOfReadRoot(batchIndex, root);
            L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

            uint256 balanceSolverBeforeSecondSettle = inputToken.balanceOf(address(vegeta));
            L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
            uint256 balanceSolverAfterSecondSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSecondSettle, balanceSolverAfterSecondSettle, "vegeta balance should not change"
            );
        }

        // Verify the final state on L1
        assertTrue(L1T17683.orderVerified(orderId), "Order should be verified");
    }

    function test_settlementWithEmptyResultData() public {
        uint256 batchIndex = 0;
        uint256 position = 0;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder();

        // 4. First, set up the proof root by calling handle on the reader

        // Construct read request calldata
        bytes memory result = hex"";
        // Generate merkle tree and proof for the result
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        // Set up the proof root in the T1ERC7683 contract
        originReader.commitProofOfReadRoot(batchIndex, root);

        // 5. Now test handleReadResultWithProof with empty result data
        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

        vm.expectEmit(true, true, true, true);
        emit T1ERC7683.SettlementVerified(orderId, false);
        L1T17683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(balanceSolverBeforeSettle, balanceSolverAfterSettle, "vegeta balance should not change");
    }

    function test_revertIfNotProver() public {
        uint256 batchIndex = 0;
        bytes32 requestId = hex"";
        bytes memory orderStatus = hex"";

        (bytes32 root,) = _generateMerkleTree(requestId, orderStatus, 0);

        vm.prank(address(0xbeef));
        vm.expectRevert(T1XChainReader.OnlyProver.selector);
        originReader.commitProofOfReadRoot(batchIndex, root);
    }

    function test_revertWithInvalidBatchIndex() public {
        uint256 batchIndex = 1;
        bytes32 requestId = bytes32(vm.randomBytes(32));
        bytes memory orderStatus = vm.randomBytes(10);

        (bytes32 root,) = _generateMerkleTree(requestId, orderStatus, 0);

        vm.expectRevert(T1XChainReader.InvalidBatchIndex.selector);
        originReader.commitProofOfReadRoot(batchIndex, root);
    }

    function _openAndFillOrder() internal returns (OrderData memory, bytes32 orderId, bytes32 requestId) {
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(L1T17683), amount);
        vm.recordLogs();
        L1T17683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(L1T17683.orderStatus(orderId_), _base7683.OPENED());

        vm.startPrank(vegeta);
        outputToken.approve(address(L2T17683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        L2T17683.fill(orderId_, originData, fillerData);
        assertEq(L2T17683.orderStatus(orderId_), L2T17683.FILLED());
        vm.stopPrank();

        vm.startPrank(vegeta);
        bytes32 requestId_ = L1T17683.verifySettlement(destination, 1_000_000, orderId_);
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
