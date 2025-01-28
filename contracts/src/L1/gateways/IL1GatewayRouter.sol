// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IL1ETHGateway } from "./IL1ETHGateway.sol";
import { IL1ERC20Gateway } from "./IL1ERC20Gateway.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

interface IL1GatewayRouter is IL1ETHGateway, IL1ERC20Gateway {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when the address of ETH Gateway is updated.
    /// @param oldETHGateway The address of the old ETH Gateway.
    /// @param newEthGateway The address of the new ETH Gateway.
    event SetETHGateway(address indexed oldETHGateway, address indexed newEthGateway);

    /// @notice Emitted when the address of default ERC20 Gateway is updated.
    /// @param oldDefaultERC20Gateway The address of the old default ERC20 Gateway.
    /// @param newDefaultERC20Gateway The address of the new default ERC20 Gateway.
    event SetDefaultERC20Gateway(address indexed oldDefaultERC20Gateway, address indexed newDefaultERC20Gateway);

    /// @notice Emitted when the `gateway` for `token` is updated.
    /// @param token The address of token updated.
    /// @param oldGateway The corresponding address of the old gateway.
    /// @param newGateway The corresponding address of the new gateway.
    event SetERC20Gateway(address indexed token, address indexed oldGateway, address indexed newGateway);

    /// @notice Emitted when a swap occurs.
    /// @param sender The address of the user performing the swap.
    /// @param inputToken The address of the token being swapped.
    /// @param outputToken The address of the token received.
    /// @param inputAmount The amount of the input token swapped.
    /// @param outputAmount The amount of the output token received.
    /// @param rate The rate provided for the swap.
    event Swap(
        address indexed sender,
        address indexed inputToken,
        address indexed outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 rate
    );

    /// @notice Emitted when the address of SignatureTransfer is updated.
    /// @param oldSignatureTransfer The address of the old SignatureTransfer.
    /// @param newSignatureTransfer The address of the new SignatureTransfer.
    event SetSignatureTransfer(address indexed oldSignatureTransfer, address indexed newSignatureTransfer);

    /// @notice Emitted when the address of AllowanceTransfer is updated.
    /// @param oldAllowanceTransfer The address of the old AllowanceTransfer.
    /// @param newAllowanceTransfer The address of the new AllowanceTransfer.
    event SetAllowanceTransfer(address indexed oldAllowanceTransfer, address indexed newAllowanceTransfer);

    /**
     *
     * Public View Functions *
     *
     */

    /// @notice Return the corresponding gateway address for given token address.
    /// @param _token The address of token to query.
    function getERC20Gateway(address _token) external view returns (address);

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @notice Request ERC20 token transfer from users to gateways.
    /// @param sender The address of sender to request fund.
    /// @param token The address of token to request.
    /// @param amount The amount of token to request.
    function requestERC20(address sender, address token, uint256 amount) external returns (uint256);

    /// @notice Swaps ERC20 tokens on behalf of an user using reserves in the defaultERC20Gateway.
    /// @dev The user provides an EIP-712 signature to authorize the swap.
    /// @param permit The signed permit message for a single token transfer.
    /// @param outputToken The address of the token to receive.
    /// @param providedRate The rate at which the user wishes to swap (scaled to 18 decimals).
    /// @param owner The address of the user on whose behalf the swap is executed.
    /// @param witness Extra data to include when checking the user signature.
    /// @param witnessTypeString The EIP-712 type definition for remaining string stub of the typehash.
    /// @param permitSignature The EIP-712 signature authorizing the transfer from `from` via Permit2.
    /// @return outputAmount The amount of the output token received.
    function swapERC20(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        address outputToken,
        uint256 providedRate,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata permitSignature
    )
        external
        returns (uint256 outputAmount);

    /**
     *
     * Restricted Functions *
     *
     */

    /// @notice Update the address of ETH gateway contract.
    /// @dev This function should only be called by contract owner.
    /// @param _ethGateway The address to update.
    function setETHGateway(address _ethGateway) external;

    /// @notice Update the address of default ERC20 gateway contract.
    /// @dev This function should only be called by contract owner.
    /// @param _defaultERC20Gateway The address to update.
    function setDefaultERC20Gateway(address _defaultERC20Gateway) external;

    /// @notice Update the mapping from token address to gateway address.
    /// @dev This function should only be called by contract owner.
    /// @param _tokens The list of addresses of tokens to update.
    /// @param _gateways The list of addresses of gateways to update.
    function setERC20Gateway(address[] calldata _tokens, address[] calldata _gateways) external;

    /// @notice Update the address of SignatureTransfer contract.
    /// @dev This function should only be called by contract owner.
    /// @param _signatureTransfer The address to update.
    function setSignatureTransfer(address _signatureTransfer) external;

    /// @notice Update the address of AllowanceTransfer contract.
    /// @dev This function should only be called by contract owner.
    /// @param _allowanceTransfer The address to update.
    function setAllowanceTransfer(address _allowanceTransfer) external;
}
