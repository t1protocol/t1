// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Merkle } from "../../../murky/src/Merkle.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
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

    Merkle internal tree = new Merkle();
    uint256 internal treePosition = 0;

    function test_ERC7683BatchSolverRepayment_sameSolver() public {
        (MerkleLeafHelper memory merkleLeafHelper0) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_0, 0);
        (MerkleLeafHelper memory merkleLeafHelper1) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_1, 1);
        (MerkleLeafHelper memory merkleLeafHelper2) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_2, 2);
        (MerkleLeafHelper memory merkleLeafHelper3) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_3, 3);
        (MerkleLeafHelper memory merkleLeafHelper4) =
            _openFillOrder_and_generateMerkleLeaf(kakaroto, vegeta, SOME_AMOUNT_4, 4);

        bytes32[] memory treeLeaves = new bytes32[](5);
        treeLeaves[0] = merkleLeafHelper0.treeLeaf;
        treeLeaves[1] = merkleLeafHelper1.treeLeaf;
        treeLeaves[2] = merkleLeafHelper2.treeLeaf;
        treeLeaves[3] = merkleLeafHelper3.treeLeaf;
        treeLeaves[4] = merkleLeafHelper4.treeLeaf;

        originReader.commitProofOfReadRoot(batchIndex, tree.getRoot(treeLeaves));

        {
            uint256 balanceSolverBeforeSettle = inputToken.balanceOf(address(vegeta));

            bytes[] memory encodedProofs = new bytes[](5);
            encodedProofs[0] = abi.encode(batchIndex, merkleLeafHelper0.requestId, 0, merkleLeafHelper0.result, abi.encodePacked(tree.getProof(treeLeaves, 0)));
            encodedProofs[1] = abi.encode(batchIndex, merkleLeafHelper1.requestId, 1, merkleLeafHelper1.result, abi.encodePacked(tree.getProof(treeLeaves, 1)));
            encodedProofs[2] = abi.encode(batchIndex, merkleLeafHelper2.requestId, 2, merkleLeafHelper2.result, abi.encodePacked(tree.getProof(treeLeaves, 2)));
            encodedProofs[3] = abi.encode(batchIndex, merkleLeafHelper3.requestId, 3, merkleLeafHelper3.result, abi.encodePacked(tree.getProof(treeLeaves, 3)));
            encodedProofs[4] = abi.encode(batchIndex, merkleLeafHelper4.requestId, 4, merkleLeafHelper4.result, abi.encodePacked(tree.getProof(treeLeaves, 4)));

            l1T1ERC7683.handleBatchOfReadResultsWithProofs(encodedProofs);

            uint256 balanceSolverAfterSettle = inputToken.balanceOf(address(vegeta));

            assertEq(
                balanceSolverBeforeSettle + SOME_AMOUNT_0 + SOME_AMOUNT_1 + SOME_AMOUNT_2 + SOME_AMOUNT_3
                    + SOME_AMOUNT_4,
                balanceSolverAfterSettle,
                "vegeta balance increased by batch inputs amount"
            );
        }

        // Verify the final state on L1
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper0.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order0 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper1.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order1 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper2.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order2 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper3.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order3 should be settled");
        assertEq(uint8(l1T1ERC7683.orderStatus(merkleLeafHelper4.orderId)), uint8(IT1ERC7683.Status.SETTLED), "Order4 should be settled");
    }

    function _openFillOrder_and_generateMerkleLeaf(
        address opener,
        address solver,
        uint256 amount,
        uint256 batchIndex
    )
        internal
        returns (MerkleLeafHelper memory merkleLeafHelper)
    {
        (, bytes32 orderId, bytes32 requestId) = _openAndFillOrder(opener, solver, amount);

        bytes memory result = abi.encode(l2T1ERC7683.getFilledOrderStatus(merkleLeafHelper.orderId));

        bytes32 xChainReadResultHash = keccak256(merkleLeafHelper.result);

        bytes32 treeLeaf = keccak256(abi.encodePacked(xChainReadResultHash, merkleLeafHelper.requestId));

        merkleLeafHelper = MerkleLeafHelper({
            orderId: orderId,
            treeLeaf: treeLeaf,
            result: result,
            requestId: requestId
        });
    }
}
