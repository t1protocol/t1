// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPermit2, ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { ResolvedCrossChainOrder } from "../interfaces/IERC7683.sol";

/// @title T1Permit2
/// @notice Abstract contract that handles Permit2 integration for gasless cross-chain order transactions.
/// @author BootNode
/// @dev Provides functionality for signature-based token transfers using Uniswap's Permit2 system,
/// enabling gasless order operations where users can sign permit messages instead of making on-chain approvals.
/// This contract manages nonce tracking and signature validation for gasless transactions.
abstract contract T1Permit2 {
    // ============ Constants ============
    /// @notice The instance of the Permit2 contract.
    IPermit2 public immutable PERMIT2;

    /// @notice Type hash used for encoding ResolvedCrossChainOrder.
    bytes32 public constant RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH = keccak256(
        "ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)"
    );

    /// @notice The witness type string used in PERMIT2 transactions.
    string public constant witnessTypeString =
        "ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)TokenPermissions(address token,uint256 amount)";

    // ============ Public Storage ============

    /// @notice Tracks the used nonces for each address.
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    // ============ Events ============

    /// @notice Emitted when a nonce is invalidated for an address.
    /// @param owner The address whose nonce was invalidated.
    /// @param nonce The invalidated nonce.
    event NonceInvalidation(address indexed owner, uint256 nonce);

    // ============ Errors ============

    error InvalidNonce();

    // ============ Constructor ============
    /// @notice Initializes the contract with the given Permit2 contract address.
    /// @param _permit2 The address of the Permit2 contract.
    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
    }

    // ============ External Functions ============

    /// @notice Invalidates a nonce for the user calling the function.
    /// @param _nonce The nonce to invalidate.
    function invalidateNonces(uint256 _nonce) external virtual {
        _useNonce(msg.sender, _nonce);

        emit NonceInvalidation(msg.sender, _nonce);
    }

    /// @notice Checks whether a given nonce is valid.
    /// @param _from The address whose nonce validity is being checked.
    /// @param _nonce The nonce to check.
    /// @return isValid True if the nonce is valid, false otherwise.
    function isValidNonce(address _from, uint256 _nonce) external view virtual returns (bool) {
        return !usedNonces[_from][_nonce];
    }

    // ============ Public Functions ============

    /// @notice Computes the Permit2 witness hash for a given ResolvedCrossChainOrder.
    /// @param _resolvedOrder The ResolvedCrossChainOrder to compute the witness hash for.
    /// @return The computed witness hash.
    function witnessHash(ResolvedCrossChainOrder memory _resolvedOrder) public pure virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH,
                _resolvedOrder.user,
                _resolvedOrder.originChainId,
                _resolvedOrder.openDeadline,
                _resolvedOrder.fillDeadline,
                _resolvedOrder.maxSpent,
                _resolvedOrder.minReceived,
                _resolvedOrder.fillInstructions
            )
        );
    }

    // ============ Internal Functions ============

    /// @notice Marks a nonce as used by setting its bit in the appropriate bitmap.
    /// @dev Ensures that a nonce cannot be reused by flipping the corresponding bit in the bitmap.
    /// Reverts if the nonce is already used.
    /// @param _from The address for which the nonce is being used.
    /// @param _nonce The nonce to mark as used.
    function _useNonce(address _from, uint256 _nonce) internal {
        if (usedNonces[_from][_nonce]) revert InvalidNonce();
        usedNonces[_from][_nonce] = true;
    }

    /// @notice Executes a batch token transfer using the Permit2 `permitWitnessTransferFrom` method.
    /// @dev Transfers tokens specified in a resolved cross-chain order to the receiver.
    /// @param _resolvedOrder The resolved order specifying tokens and amounts to transfer.
    /// @param _signature The user's signature for the permit.
    /// @param _nonce The unique nonce associated with the order.
    /// @param _receiver The address that will receive the tokens.
    function _permitTransferFrom(
        ResolvedCrossChainOrder memory _resolvedOrder,
        bytes calldata _signature,
        uint256 _nonce,
        address _receiver
    )
        internal
    {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](_resolvedOrder.minReceived.length);

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](_resolvedOrder.minReceived.length);

        for (uint256 i = 0; i < _resolvedOrder.minReceived.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({
                token: TypeCasts.bytes32ToAddress(_resolvedOrder.minReceived[i].token),
                amount: _resolvedOrder.minReceived[i].amount
            });
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails({
                to: _receiver,
                requestedAmount: _resolvedOrder.minReceived[i].amount
            });
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: _nonce,
            deadline: _resolvedOrder.openDeadline
        });

        PERMIT2.permitWitnessTransferFrom(
            permit, transferDetails, _resolvedOrder.user, witnessHash(_resolvedOrder), witnessTypeString, _signature
        );
    }
}
