// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

library T1Constants {
    /// @notice The address of default cross chain message sender.
    address internal constant DEFAULT_XDOMAIN_MESSAGE_SENDER = address(1);

    /// @notice The address for dropping message.
    /// @dev The first 20 bytes of keccak("drop")
    address internal constant DROP_XDOMAIN_MESSAGE_SENDER = 0x6f297C61B5C92eF107fFD30CD56AFFE5A273e841;

    /// @notice Chain ID of the L1 network
    uint64 internal constant L1_CHAIN_ID = 11_155_111;

    /// @notice Chain ID of the T1 devnet
    uint64 internal constant T1_DEVNET_CHAIN_ID = 3_151_908;

    /// @notice The EIP-712 type definition for remaining string stub of the typehash.
    string internal constant WITNESS_TYPE_STRING =
    // solhint-disable-next-line max-line-length
        "Witness witness)TokenPermissions(address token,uint256 amount)Witness(uint8 direction,uint256 priceAfterSlippage,address outputTokenAddress,uint256 outputTokenAmount)";

    /// @notice The full EIP-712 type definition for the witness the typehash.
    bytes32 internal constant FULL_WITNESS_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,Witness witness)TokenPermissions(address token,uint256 amount)Witness(uint8 direction,uint256 priceAfterSlippage,address outputTokenAddress,uint256 outputTokenAmount)"
    );
}
