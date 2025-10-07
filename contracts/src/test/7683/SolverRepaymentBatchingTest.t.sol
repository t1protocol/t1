// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { T1Merkle } from "./T1Merkle.sol";

import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";

import { T1XChainReaderTest } from "./T1XChainReaderTest.t.sol";

struct MerkleLeafHelper {
    bytes32 orderId;
    bytes32 treeLeaf;
    bytes result;
    bytes32 requestId;
}

contract SolverRepaymentBatchingTest is T1XChainReaderTest {

    T1Merkle internal tree = new T1Merkle();

    function test_ERC7683BatchSolverRepayment_sameSolver_withBatching() public {
        uint256 n = 100;
        uint256[] memory amounts = _generateRandomArray(n);
        uint256 summedAmounts = 0;

        bytes32[] memory treeLeaves = new bytes32[](n);
        MerkleLeafHelper[] memory helpers = new MerkleLeafHelper[](n);
        for (uint i = 0; i < n; i++) {
            helpers[i] = _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, amounts[i]);
            treeLeaves[i] = helpers[i].treeLeaf;
            summedAmounts += amounts[i];
        }

        bytes32 root = tree.getRoot(treeLeaves);
        originReader.commitProofOfReadRoot(batchIndex, root);

        bytes[] memory encodedProofs = new bytes[](n);
        for (uint i = 0; i < n; i++) {
            bytes memory flattenedProof = _flattenProof(tree.getProof(treeLeaves, i));
            encodedProofs[i] = abi.encode(batchIndex, helpers[i].requestId, i, helpers[i].result, flattenedProof);
        }

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

        l1T1ERC7683.handleBatchOfReadResultsWithProofs(encodedProofs);

        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + summedAmounts,
            balanceSolverAfterSettle,
            "vegeta balance increased by batch inputs amount"
        );

        for (uint i = 0; i < n; i++) {
            assertEq(uint8(l1T1ERC7683.orderStatus(helpers[i].orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
        }
    }

    function test_ERC7683BatchSolverRepayment_sameSolver_noBatching() public {
        uint256 n = 100;
        uint256[] memory amounts = _generateRandomArray(n);
        uint256 summedAmounts = 0;

        bytes32[] memory treeLeaves = new bytes32[](n);
        MerkleLeafHelper[] memory helpers = new MerkleLeafHelper[](n);
        for (uint i = 0; i < n; i++) {
            helpers[i] = _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, amounts[i]);
            treeLeaves[i] = helpers[i].treeLeaf;
            summedAmounts += amounts[i];
        }

        bytes32 root = tree.getRoot(treeLeaves);
        originReader.commitProofOfReadRoot(batchIndex, root);

        bytes[] memory encodedProofs = new bytes[](n);
        for (uint i = 0; i < n; i++) {
            bytes memory flattenedProof = _flattenProof(tree.getProof(treeLeaves, i));
            encodedProofs[i] = abi.encode(batchIndex, helpers[i].requestId, i, helpers[i].result, flattenedProof);
        }

        uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

        for (uint i = 0; i < n; i++) {
            l1T1ERC7683.handleReadResultWithProof(encodedProofs[i]);
        }

        uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

        assertEq(
            balanceSolverBeforeSettle + summedAmounts,
            balanceSolverAfterSettle,
            "vegeta balance increased by batch inputs amount"
        );

        for (uint i = 0; i < n; i++) {
            assertEq(uint8(l1T1ERC7683.orderStatus(helpers[i].orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order should be settled");
        }
    }

    function _openFillOrder_and_generateMerkleLeaf(
        address opener,
        address solver,
        uint256 amount
    ) internal returns (MerkleLeafHelper memory merkleLeafHelper) {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(opener, solver, amount);
        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(orderId));
        bytes32 xChainReadResultHash = keccak256(result);
        bytes32 treeLeaf = keccak256(abi.encodePacked(xChainReadResultHash, requestId));
        merkleLeafHelper = MerkleLeafHelper({
            orderId: orderId,
            treeLeaf: treeLeaf,
            result: result,
            requestId: requestId
        });
    }

    function _flattenProof(bytes32[] memory proof) internal pure returns (bytes memory proofBytes) {
        proofBytes = new bytes(proof.length * 32);
        for (uint256 i = 0; i < proof.length; i++) {
            assembly {
                // store each 32-byte element at the correct offset
                mstore(add(proofBytes, add(32, mul(i, 32))), mload(add(proof, add(32, mul(i, 32)))))
            }
        }
    }

    function _generateRandomArray(uint256 length) internal view returns (uint256[] memory arr) {
        arr = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % 1000;
        }
    }
}
