
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";

library BatchHeaders {
    function generateBatchHeader(T1ChainMockBlob rollup) internal view returns (bytes memory batchHeader1) {
        batchHeader1 = new bytes(193);
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory blobDataProof =
        // solhint-disable-next-line max-line-length
            hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        assembly {
            mstore8(add(batchHeader1, 0x20), 3) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            // dataHash
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51)
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), 0) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        batchHeader1[1] = bytes1(uint8(0)); // change back
    }
}