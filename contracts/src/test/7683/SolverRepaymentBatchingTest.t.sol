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
    uint256 internal SOME_AMOUNT_0 = 117;
    uint256 internal SOME_AMOUNT_1 = 77;
    uint256 internal SOME_AMOUNT_2 = 125;
    uint256 internal SOME_AMOUNT_3 = 136;
    uint256 internal SOME_AMOUNT_4 = 53;

    T1Merkle internal tree = new T1Merkle();

    function test_ERC7683BatchSolverRepayment_sameSolver() public {
        (MerkleLeafHelper memory merkleLeafHelper0) =
                        _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_0);
        (MerkleLeafHelper memory merkleLeafHelper1) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_1);
        (MerkleLeafHelper memory merkleLeafHelper2) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_2);
        (MerkleLeafHelper memory merkleLeafHelper3) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_3);
        (MerkleLeafHelper memory merkleLeafHelper4) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_4);

        bytes32[] memory treeLeaves = new bytes32[](5);
        treeLeaves[0] = merkleLeafHelper0.treeLeaf;
        treeLeaves[1] = merkleLeafHelper1.treeLeaf;
        treeLeaves[2] = merkleLeafHelper2.treeLeaf;
        treeLeaves[3] = merkleLeafHelper3.treeLeaf;
        treeLeaves[4] = merkleLeafHelper4.treeLeaf;

        bytes32 root = tree.getRoot(treeLeaves);
        originReader.commitProofOfReadRoot(batchIndex, root);

        bytes memory proof0 = _flattenProof(tree.getProof(treeLeaves, 0));
        bytes memory proof1 = _flattenProof(tree.getProof(treeLeaves, 1));
        bytes memory proof2 = _flattenProof(tree.getProof(treeLeaves, 2));
        bytes memory proof3 = _flattenProof(tree.getProof(treeLeaves, 3));
        bytes memory proof4 = _flattenProof(tree.getProof(treeLeaves, 4));

        {
            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

            bytes[] memory encodedProofs = new bytes[](5);
            encodedProofs[0] = abi.encode(batchIndex, merkleLeafHelper0.requestId, 0, merkleLeafHelper0.result, proof0);
            encodedProofs[1] = abi.encode(batchIndex, merkleLeafHelper1.requestId, 1, merkleLeafHelper1.result, proof1);
            encodedProofs[2] = abi.encode(batchIndex, merkleLeafHelper2.requestId, 2, merkleLeafHelper2.result, proof2);
            encodedProofs[3] = abi.encode(batchIndex, merkleLeafHelper3.requestId, 3, merkleLeafHelper3.result, proof3);
            encodedProofs[4] = abi.encode(batchIndex, merkleLeafHelper4.requestId, 4, merkleLeafHelper4.result, proof4);

            l1T1ERC7683.handleBatchOfReadResultsWithProofs(encodedProofs);

            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + SOME_AMOUNT_0 + SOME_AMOUNT_1 + SOME_AMOUNT_2 + SOME_AMOUNT_3
                    + SOME_AMOUNT_4,
                balanceSolverAfterSettle,
                "vegeta balance increased by batch inputs amount"
            );
        }

        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper0.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order0 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper1.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order1 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper2.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order2 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper3.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order3 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper4.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order4 should be settled");
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
}
