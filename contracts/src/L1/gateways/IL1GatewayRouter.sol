// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

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
    event Swap(
        address indexed sender,
        address indexed inputToken,
        address indexed outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    );

    /// @notice Emitted when the address of Permit2 is updated.
    /// @param oldPermit2 The address of the old Permit2.
    /// @param newPermit2 The address of the new Permit2.
    event SetPermit2(address indexed oldPermit2, address indexed newPermit2);

    /// @notice Emitted when the market maker is updated.
    /// @param oldMM The address of the old market maker.
    /// @param newMM The address of the new market maker.
    event SetMM(address indexed oldMM, address indexed newMM);

    /// @notice Represents the extra details for the swap
    /// @param direction External swap direction (irrelevant for internal swaps)
    /// @param priceAfterSlippage External price after slippage (irrelevant for internal swaps)
    /// @param outputTokenAddress Output token address
    /// @param outputTokenAmount Output token amount
    struct Witness {
        uint8 direction;
        uint256 priceAfterSlippage;
        address outputTokenAddress;
        uint256 outputTokenAmount;
    }

    /// @notice Represents the necessary details for the swap
    /// @param permit The signed permit message for a single token transfer.
    /// @param owner The address of the user on whose behalf the swap is executed.
    /// @param witness The struct containing the extra details of the swap.
    /// @param sig The EIP-712 signature authorizing the transfer from the owner via Permit2.
    struct SwapParams {
        ISignatureTransfer.PermitTransferFrom permit;
        address owner;
        Witness witness;
        bytes sig;
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @notice Return the corresponding gateway address for given token address.
    /// @param _token The address of token to query.
    function getERC20Gateway(address _token) external view returns (address);

    /// @notice Return the current Allowance Transfer contract address
    function permit2() external view returns (address);

    /// @notice Return the current market maker address
    function marketMaker() external view returns (address);

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
    /// @param params The Struct that includes details for the swap.
    /// @dev The user provides an EIP-712 signature to authorize the swap.
    function swapERC20(SwapParams calldata params) external;

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

    /// @notice Update the address of Permit2 contract.
    /// @dev This function should only be called by contract owner.
    /// @param _newPermit2 The address to update.
    function setPermit2(address _newPermit2) external;

    /// @notice Update the address of the market maker.
    /// @dev This function should only be called by contract owner.
    /// @param _newMM The address to update.
    function setMM(address _newMM) external;
}
