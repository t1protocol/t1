// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IRollupVerifier } from "../../libraries/verifier/IRollupVerifier.sol";
import { IZkEvmVerifierV1, IZkEvmVerifierV2 } from "../../libraries/verifier/IZkEvmVerifier.sol";

/// @title MultipleVersionRollupVerifier
/// @notice Verifies aggregate zk proofs using the appropriate verifier.
contract MultipleVersionRollupVerifier is IRollupVerifier, Ownable {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when the address of verifier is updated.
    /// @param version The version of the verifier.
    /// @param startBatchIndex The start batch index when the verifier will be used.
    /// @param verifier The address of new verifier.
    event UpdateVerifier(uint256 version, uint256 startBatchIndex, address verifier);

    /**
     *
     * Errors *
     *
     */

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /// @dev Thrown when the given start batch index is smaller than `latestVerifier.startBatchIndex`.
    error ErrorStartBatchIndexTooSmall();

    /**
     *
     * Structs *
     *
     */
    struct Verifier {
        // The start batch index for the verifier.
        uint64 startBatchIndex;
        // The address of zkevm verifier.
        address verifier;
    }

    /**
     *
     * Variables *
     *
     */

    /// @notice Mapping from verifier version to the list of legacy zkevm verifiers.
    /// The verifiers are sorted by batchIndex in increasing order.
    mapping(uint256 => Verifier[]) public legacyVerifiers;

    /// @notice Mapping from verifier version to the latest used zkevm verifier.
    mapping(uint256 => Verifier) public latestVerifier;

    /**
     *
     * Constructor *
     *
     */
    constructor(uint256[] memory _versions, address[] memory _verifiers) {
        for (uint256 i = 0; i < _versions.length; i++) {
            if (_verifiers[i] == address(0)) revert ErrorZeroAddress();
            latestVerifier[_versions[i]].verifier = _verifiers[i];

            emit UpdateVerifier(_versions[i], 0, _verifiers[i]);
        }
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @notice Return the number of legacy verifiers.
    /// @param _version The version of legacy verifiers.
    /// @return The number of legacy verifiers.
    function legacyVerifiersLength(uint256 _version) external view returns (uint256) {
        return legacyVerifiers[_version].length;
    }

    /// @notice Compute the verifier should be used for specific batch.
    /// @param _version The version of verifier to query.
    /// @param _batchIndex The batch index to query.
    /// @return The address of verifier.
    function getVerifier(uint256 _version, uint256 _batchIndex) public view returns (address) {
        // Normally, we will use the latest verifier.
        Verifier memory _verifier = latestVerifier[_version];

        if (_verifier.startBatchIndex > _batchIndex) {
            uint256 _length = legacyVerifiers[_version].length;
            // In most case, only last few verifier will be used by `T1Chain`.
            // So, we use linear search instead of binary search.
            unchecked {
                for (uint256 i = _length; i > 0; --i) {
                    _verifier = legacyVerifiers[_version][i - 1];
                    if (_verifier.startBatchIndex <= _batchIndex) break;
                }
            }
        }

        return _verifier.verifier;
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IRollupVerifier
    function verifyAggregateProof(
        uint256 _batchIndex,
        bytes calldata _aggrProof,
        bytes32 _publicInputHash
    )
        external
        view
        override
    {
        address _verifier = getVerifier(0, _batchIndex);

        IZkEvmVerifierV1(_verifier).verify(_aggrProof, _publicInputHash);
    }

    /// @inheritdoc IRollupVerifier
    function verifyAggregateProof(
        uint256 _version,
        uint256 _batchIndex,
        bytes calldata _aggrProof,
        bytes32 _publicInputHash
    )
        external
        view
        override
    {
        address _verifier = getVerifier(_version, _batchIndex);

        IZkEvmVerifierV1(_verifier).verify(_aggrProof, _publicInputHash);
    }

    /// @inheritdoc IRollupVerifier
    function verifyBundleProof(
        uint256 _version,
        uint256 _batchIndex,
        bytes calldata _bundleProof,
        bytes calldata _publicInput
    )
        external
        view
        override
    {
        address _verifier = getVerifier(_version, _batchIndex);

        IZkEvmVerifierV2(_verifier).verify(_bundleProof, _publicInput);
    }

    /**
     *
     * Restricted Functions *
     *
     */

    /// @notice Update the address of zkevm verifier.
    /// @param _version The version of the verifier.
    /// @param _startBatchIndex The start batch index when the verifier will be used.
    /// @param _verifier The address of new verifier.
    function updateVerifier(uint256 _version, uint64 _startBatchIndex, address _verifier) external onlyOwner {
        // We are using version to decide the verifier to use and also this function is
        // controlled by 7 days TimeLock. It is hard to predict `lastFinalizedBatchIndex` after 7 days.
        // So we decide to remove this check to make verifier updating more easier.
        // if (_startBatchIndex <= IT1Chain(T1Chain).lastFinalizedBatchIndex())
        //    revert ErrorStartBatchIndexFinalized();

        Verifier memory _latestVerifier = latestVerifier[_version];
        if (_startBatchIndex < _latestVerifier.startBatchIndex) revert ErrorStartBatchIndexTooSmall();
        if (_verifier == address(0)) revert ErrorZeroAddress();

        if (_latestVerifier.startBatchIndex < _startBatchIndex) {
            // don't push when it is the first update of the version.
            if (_latestVerifier.verifier != address(0)) {
                legacyVerifiers[_version].push(_latestVerifier);
            }
            _latestVerifier.startBatchIndex = _startBatchIndex;
        }
        _latestVerifier.verifier = _verifier;

        latestVerifier[_version] = _latestVerifier;

        emit UpdateVerifier(_version, _startBatchIndex, _verifier);
    }
}
