// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

/// @title IRollupVerifier
/// @notice The interface for rollup verifier.
interface IRollupVerifier {
    /// @notice Verify aggregate zk proof.
    /// @param batchIndex The batch index to verify.
    /// @param aggrProof The aggregated proof.
    /// @param publicInputHash The public input hash.
    function verifyAggregateProof(
        uint256 batchIndex,
        bytes calldata aggrProof,
        bytes32 publicInputHash
    )
        external
        view;

    /// @notice Verify aggregate zk proof.
    /// @param version The version of verifier to use.
    /// @param batchIndex The batch index to verify.
    /// @param aggrProof The aggregated proof.
    /// @param publicInputHash The public input hash.
    function verifyAggregateProof(
        uint256 version,
        uint256 batchIndex,
        bytes calldata aggrProof,
        bytes32 publicInputHash
    )
        external
        view;

    /// @notice Verify bundle zk proof.
    /// @param version The version of verifier to use.
    /// @param batchIndex The batch index used to select verifier.
    /// @param bundleProof The aggregated proof.
    /// @param publicInput The public input.
    function verifyBundleProof(
        uint256 version,
        uint256 batchIndex,
        bytes calldata bundleProof,
        bytes calldata publicInput
    )
        external
        view;
}
