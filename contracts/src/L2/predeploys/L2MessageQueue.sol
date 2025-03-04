// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AppendOnlyMerkleTree } from "../../libraries/common/AppendOnlyMerkleTree.sol";
import { OwnableBase } from "../../libraries/common/OwnableBase.sol";
import { IL2GasPriceOracle } from "../../L1/rollup/IL2GasPriceOracle.sol";

/// @title L2MessageQueue
/// @notice The original idea is from Optimism, see
// solhint-disable-next-line max-line-length
/// [OVM_L2ToL1MessagePasser](https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts/contracts/L2/predeploys/OVM_L2ToL1MessagePasser.sol).
/// The L2 to L1 Message Passer is a utility contract which facilitate an L1 proof of the
/// of a message on L2. The L1 Cross Domain Messenger performs this proof in its
/// _verifyStorageProof function, which verifies the existence of the transaction hash in this
/// contract's `sentMessages` mapping.
contract L2MessageQueue is AppendOnlyMerkleTree, OwnableBase {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when a new message is added to the merkle tree.
    /// @param index The index of the corresponding message.
    /// @param messageHash The hash of the corresponding message.
    event AppendMessage(uint256 index, bytes32 messageHash);

    /**
     *
     * Variables *
     *
     */

    /// @notice The address of L2T1Messenger contract.
    address public messenger;

    /// @notice Maps chain IDs to the address of the GasOracle contract responsible for reporting the gas for that
    /// network.
    mapping(uint64 chainId => address gasOracle) public gasOraclesByChain;

    /**
     *
     * Constructor *
     *
     */
    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    /// @notice Initialize the state of `L2MessageQueue`
    /// @dev You are not allowed to initialize when there are some messages appended.
    /// @param _messenger The address of messenger to update.
    function initialize(address _messenger) external onlyOwner {
        require(nextMessageIndex == 0, "cannot initialize");

        _initializeMerkleTree();

        messenger = _messenger;
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @notice record the message to merkle tree and compute the new root.
    /// @param _messageHash The hash of the new added message.
    function appendMessage(bytes32 _messageHash) external returns (bytes32) {
        require(msg.sender == messenger, "only messenger");

        (uint256 _currentNonce, bytes32 _currentRoot) = _appendMessageHash(_messageHash);

        // We can use the event to compute the merkle tree locally.
        emit AppendMessage(_currentNonce, _messageHash);

        return _currentRoot;
    }

    /// @notice Set the gas oracle for a specific chain ID
    /// @param _chainId The ID of the chain to set the oracle for
    /// @param _oracle The address of the gas oracle contract
    function setGasOracle(uint64 _chainId, address _oracle) external onlyOwner {
        gasOraclesByChain[_chainId] = _oracle;
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @notice Return the amount of ETH should pay for cross domain message.
    /// @param _gasLimit Gas limit required to complete the message relay on destination L2.
    /// @param _chainId The ID of the destination chain.
    /// @return fee The amount of ETH required to pay for the cross domain message, or 0 if no gas oracle is set for the
    /// chain
    function estimateCrossDomainMessageFee(uint256 _gasLimit, uint64 _chainId) external view returns (uint256) {
        address _oracle = gasOraclesByChain[_chainId];
        if (_oracle == address(0)) return 0;
        return IL2GasPriceOracle(_oracle).estimateCrossDomainMessageFee(_gasLimit);
    }
}
