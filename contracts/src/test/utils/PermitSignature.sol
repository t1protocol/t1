// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

contract PermitSignature is DSTestPlus {
    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function getPermitWitnessTransferSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 privateKey,
        bytes32 typehash,
        bytes32 witness,
        bytes32 domainSeparator,
        address spender
    )
        internal
        returns (bytes memory sig)
    {
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(typehash, tokenPermissions, spender, permit.nonce, permit.deadline, witness))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
