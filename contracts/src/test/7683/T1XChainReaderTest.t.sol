// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";
import { IT1XChainReader } from "../../libraries/xChain/IT1XChainReader.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";

contract T1XChainReaderTest is T1XChainReaderBaseTestSetup {
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
        l1T1ERC7683.initialize(address(l2T1ERC7683), auctionWitness);
        l2T1ERC7683.initialize(address(l1T1ERC7683), auctionWitness);
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
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));

            // Generate merkle tree and proof for the result
            (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            originReader.commitProofOfReadRoot(batchIndex, root);
            l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
    }

    function test_ERC7683SettlementFlowWithAnotherTreePosition() public {
        position = 3;

        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        // 4. Process the read request on L2 (destination chain) & Relay the result back to L1
        {
            // Construct the read request calldata
            bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
            // Generate merkle tree and proof for the result
            (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
            originReader.commitProofOfReadRoot(batchIndex, root);
            l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
            );
        }

        // Verify the final state on L1
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
    }

    function test_shouldFillWithAmountOutHigherThanLimit() public {
        OrderData memory orderData = _prepareOrderData(amount);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId,) = _getOrderIDFromLogs();
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        uint256 amountOut = amount * 2;
        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amountOut);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amountOut, TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId, originData, fillerData);
        assertEq(uint8(l2T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.FILLED));
        vm.stopPrank();
    }

    function test_revertFillWithAmountOutLowerThanLimit() public {
        OrderData memory orderData = _prepareOrderData(amount);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId,) = _getOrderIDFromLogs();
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.OPENED));

        uint256 amountOut = amount - 1;
        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amountOut);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amountOut, TypeCasts.addressToBytes32(vegeta));
        vm.expectRevert(IT1ERC7683.AmountOutTooLow.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
    }

    function test_incrementBatchIndex() public {
        bytes32 root = bytes32(vm.randomBytes(32));

        uint256 precommitBatchIndex = originReader.nextBatchIndex();
        originReader.commitProofOfReadRoot(batchIndex, root);
        uint256 postcommitBatchIndex = originReader.nextBatchIndex();

        assertEq(precommitBatchIndex + 1, postcommitBatchIndex, "Batch index should be incremented");
    }

    function test_proverAbleToUpdatePreviousBatchIndexRoot() public {
        bytes32 root = bytes32(vm.randomBytes(32));
        bytes32 root2 = bytes32(vm.randomBytes(32));

        originReader.commitProofOfReadRoot(batchIndex, root);
        originReader.commitProofOfReadRoot(batchIndex, root2);

        assertEq(originReader.proofOfReadRoots(batchIndex), root2, "Root should be updated");
    }

    function test_revertWithInvalidProofData() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root,) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        bytes memory invalidProof = hex"11";

        vm.expectRevert("Invalid proof");
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, invalidProof));
    }

    function test_revertWithInvalidProof() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root,) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Use an invalid proof that is the correct length (64 bytes) but contains wrong data
        bytes memory invalidProof = abi.encodePacked(
            bytes32(0x1111111111111111111111111111111111111111111111111111111111111111),
            bytes32(0x2222222222222222222222222222222222222222222222222222222222222222)
        );

        vm.expectRevert(T1XChainReader.InvalidProof.selector);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, invalidProof));
    }

    function test_revertWithInvalidResultData() public {
        (,, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        // 4. First, set up the proof root by calling handle on the reader

        // Construct read request calldata
        bytes memory result = hex"11";
        // Generate merkle tree and proof for the result
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        // Set up the proof root in the T1ERC7683 contract
        originReader.commitProofOfReadRoot(batchIndex, root);

        // 5. Now test handleReadResultWithProof with invalid result data
        vm.expectRevert();
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
    }

    function test_sameProofShouldNotSettleTwice() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

        vm.expectRevert(IT1ERC7683.InvalidOrder.selector);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

        // Verify the final state on L1
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
    }

    function test_settlementIfStatusIsRefundRequested() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Moves timestamp 200 sec forward
        skip(200);

        vm.prank(kakaroto);
        l1T1ERC7683.verifyRefund(orderId);

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.REFUND_REQUESTED));

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
        vm.prank(vegeta);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
        );

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED));
    }

    function test_settlementIfReadRequestedTwice() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        // Request PoR a second time
        vm.prank(kakaroto);
        l1T1ERC7683.verifySettlement(destination, orderId);
        (root, proof) = _generateMerkleTree(requestId, result, position);
        originReader.commitProofOfReadRoot(batchIndex, root);

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));
        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + amount, balanceSolverAfterSettle, "vegeta balance increased by input amount"
        );

        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.SETTLED));
    }

    function test_settlementWithEmptyResultData() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);

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
        emit IT1ERC7683.SettlementVerified(orderId, false);
        l1T1ERC7683.handleReadResultWithProof(abi.encode(batchIndex, requestId, position, result, proof));

        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(balanceSolverBeforeSettle, balanceSolverAfterSettle, "vegeta balance should not change");
    }

    function test_revertIfNotProver() public {
        bytes32 requestId = hex"";
        bytes memory orderStatus = hex"";

        (bytes32 root,) = _generateMerkleTree(requestId, orderStatus, 0);

        vm.prank(owner);
        vm.expectRevert(T1XChainReader.OnlyProver.selector);
        originReader.commitProofOfReadRoot(batchIndex, root);
    }

    function test_revertWithInvalidBatchIndex() public {
        batchIndex = 1;
        bytes32 requestId = bytes32(vm.randomBytes(32));
        bytes memory orderStatus = vm.randomBytes(10);

        (bytes32 root,) = _generateMerkleTree(requestId, orderStatus, 0);

        vm.expectRevert(T1XChainReader.InvalidBatchIndex.selector);
        originReader.commitProofOfReadRoot(batchIndex, root);
    }

    function test_requestReadEmitsCorrectNonce() public {
        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        vm.warp(100);

        uint256 expectedNonce = originReader.nonce();
        bytes32 expectedRequestId = keccak256(
            abi.encodePacked(
                block.chainid,
                request.destinationDomain,
                request.targetContract,
                request.callData,
                block.timestamp,
                request.requester,
                expectedNonce
            )
        );

        vm.expectEmit(true, true, true, true);
        emit T1XChainReader.ReadRequested(
            expectedRequestId,
            request.destinationDomain,
            request.targetContract,
            request.requester,
            request.minBlock,
            request.callData,
            expectedNonce
        );

        bytes32 requestId_ = originReader.requestRead(request);

        assertEq(requestId_, expectedRequestId, "requestId mismatch");
        assertEq(originReader.nonce(), expectedNonce + 1, "nonce should increment");
    }

    // function test_ownerCanUpdateProver() public {
    //     address newProver = address(0xbeef);
    //     originReader.setProver(newProver);
    //     assertEq(originReader.prover(), newProver, "Prover should be updated");
    // }

    // function test_revertIfZeroAddress() public {
    //     vm.expectRevert(T1XChainReader.ZeroAddress.selector);
    //     originReader.setProver(address(0));
    // }

    // function test_revertIfNotOwner() public {
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     vm.prank(address(0xbeef));
    //     originReader.setProver(address(0xbeef));
    // }

    // ============ Fee Tests ============

    function test_setReadFee() public {
        uint256 newFee = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit T1XChainReader.FeeUpdated(newFee);

        originReader.setReadFee(newFee);

        assertEq(originReader.readFee(), newFee, "Read fee should be updated");
    }

    function test_setReadFeeOnlyOwner() public {
        uint256 newFee = 1 ether;

        vm.prank(address(0xbeef));
        vm.expectRevert("Ownable: caller is not the owner");
        originReader.setReadFee(newFee);
    }

    function test_setFeeRecipient() public {
        address newRecipient = address(0xfeed);

        vm.expectEmit(true, true, true, true);
        emit T1XChainReader.FeeRecipientUpdated(newRecipient);

        originReader.setFeeRecipient(newRecipient);

        assertEq(originReader.feeRecipient(), newRecipient, "Fee recipient should be updated");
    }

    function test_setFeeRecipientRevertZeroAddress() public {
        vm.expectRevert(T1XChainReader.ZeroAddress.selector);
        originReader.setFeeRecipient(address(0));
    }

    function test_setFeeRecipientOnlyOwner() public {
        address newRecipient = address(0xfeed);

        vm.prank(address(0xbeef));
        vm.expectRevert("Ownable: caller is not the owner");
        originReader.setFeeRecipient(newRecipient);
    }

    function test_requestReadWithFee() public {
        uint256 fee = 0.1 ether;
        address feeRecipient = address(0xfeed);

        originReader.setReadFee(fee);
        originReader.setFeeRecipient(feeRecipient);

        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        uint256 preBalance = address(originReader).balance;

        bytes32 requestId = originReader.requestRead{ value: fee }(request);

        assertEq(address(originReader).balance, preBalance + fee, "Contract balance should increase");
        assertTrue(requestId != bytes32(0), "Request ID should be valid");
    }

    function test_requestReadWithInsufficientFee() public {
        uint256 fee = 0.1 ether;
        uint256 paidFee = 0.05 ether;

        originReader.setReadFee(fee);

        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        vm.expectRevert(T1XChainReader.IncorrectFee.selector);
        originReader.requestRead{ value: paidFee }(request);
    }

    function test_requestReadWithZeroFee() public {
        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        bytes32 requestId = originReader.requestRead(request);

        assertEq(address(originReader).balance, 0, "No fees should be collected");
        assertTrue(requestId != bytes32(0), "Request ID should be valid");
    }

    function test_withdrawFees() public {
        uint256 fee = 0.1 ether;
        address feeRecipient = address(0xfeed);

        originReader.setReadFee(fee);
        originReader.setFeeRecipient(feeRecipient);

        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        originReader.requestRead{ value: fee }(request);
        originReader.requestRead{ value: fee }(request);

        uint256 preBalance = feeRecipient.balance;
        uint256 expectedWithdrawal = address(originReader).balance;

        vm.expectEmit(true, true, true, true);
        emit T1XChainReader.FeesWithdrawn(feeRecipient, expectedWithdrawal);

        vm.prank(feeRecipient);
        originReader.withdrawFees();

        assertEq(feeRecipient.balance, preBalance + expectedWithdrawal, "Fee recipient should receive fees");
        assertEq(address(originReader).balance, 0, "Contract balance should be reset");
    }

    function test_withdrawFeesUnauthorized() public {
        uint256 fee = 0.1 ether;
        address feeRecipient = address(0xfeed);

        originReader.setReadFee(fee);
        originReader.setFeeRecipient(feeRecipient);

        IT1XChainReader.ReadRequest memory request = IT1XChainReader.ReadRequest({
            destinationDomain: destination,
            targetContract: address(0xbeef),
            minBlock: 0,
            callData: hex"",
            requester: address(this)
        });

        originReader.requestRead{ value: fee }(request);

        vm.prank(address(0xbeef));
        vm.expectRevert(T1XChainReader.UnauthorizedFeeWithdraw.selector);
        originReader.withdrawFees();
    }

    function test_withdrawFeesWithNoFees() public {
        address feeRecipient = address(0xfeed);
        originReader.setFeeRecipient(feeRecipient);

        uint256 preBalance = feeRecipient.balance;

        vm.prank(feeRecipient);
        originReader.withdrawFees();

        assertEq(feeRecipient.balance, preBalance, "Fee recipient balance should not change when no fees");
    }

    function test_verifyProofOfReadWithResult() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root, bytes memory proof) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);

        // Encode the proof without the result (verifyProofOfReadWithResult expects this format)
        bytes memory encodedProofOfRead = abi.encode(batchIndex, requestId, position, proof);
        bytes32 returnedRequestId = originReader.verifyProofOfReadWithResult(encodedProofOfRead, result);

        assertEq(returnedRequestId, requestId, "Returned request ID should match expected");
    }

    function test_verifyProofOfReadWithResult_InvalidProof() public {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(kakaroto, vegeta, amount);
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        (bytes32 root,) = _generateMerkleTree(requestId, result, position);

        originReader.commitProofOfReadRoot(batchIndex, root);

        // Create an invalid proof
        bytes memory invalidProof = abi.encodePacked(
            bytes32(0x1111111111111111111111111111111111111111111111111111111111111111),
            bytes32(0x2222222222222222222222222222222222222222222222222222222222222222)
        );
        bytes memory encodedProofOfRead = abi.encode(batchIndex, requestId, position, invalidProof);

        vm.expectRevert(T1XChainReader.InvalidProof.selector);
        originReader.verifyProofOfReadWithResult(encodedProofOfRead, result);
    }

    // Auction Witness

    function test_auctionWitnessIsCorrectlyInitialized() public {
        assertEq(l1T1ERC7683.auctionWitness(), auctionWitness);
    }

    function test_updateAuctionWitness() public {
        address newAuctionWitness = makeAddr("newAuctionWitness");
        address currentAuctionWitness = l1T1ERC7683.auctionWitness();

        vm.expectEmit(true, true, false, true);
        emit IT1ERC7683.AuctionWitnessUpdated(currentAuctionWitness, newAuctionWitness);

        l1T1ERC7683.updateAuctionWitness(newAuctionWitness);

        assertEq(l1T1ERC7683.auctionWitness(), newAuctionWitness);
    }

    function test_updateAuctionWitnessRevertZeroAddress() public {
        vm.expectRevert(IT1ERC7683.ZeroAddress.selector);
        l1T1ERC7683.updateAuctionWitness(address(0));
    }

    function test_updateAuctionWitnessRevertIfNotAdmin() public {
        address newAuctionWitness = makeAddr("newAuctionWitness");
        address nonAdmin = makeAddr("nonAdmin");

        // Test revert when called by non-admin
        vm.prank(nonAdmin);
        vm.expectRevert();
        l1T1ERC7683.updateAuctionWitness(newAuctionWitness);
    }
}
