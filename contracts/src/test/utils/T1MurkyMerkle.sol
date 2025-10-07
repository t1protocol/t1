// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MurkyMerkleBase } from "./MurkyMerkleBase.sol";

/// @notice Nascent, simple, kinda efficient (and improving!) Merkle proof generator and verifier
/// @author dmfxyz
/// @dev Note Generic Merkle Tree
contract T1MurkyMerkle is MurkyMerkleBase {
    /**
     *
     * HASHING FUNCTION *
     *
     */

    /// ascending sort and concat prior to hashing
    function hashLeafPairs(bytes32 left, bytes32 right) public pure override returns (bytes32 _hash) {
        assembly {
            mstore(0x00, left)
            mstore(0x20, right)
            _hash := keccak256(0x00, 0x40)
        }
    }
}
