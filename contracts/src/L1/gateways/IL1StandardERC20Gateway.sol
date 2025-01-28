// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

interface IL1StandardERC20Gateway {
    /**
     *
     * Events *
     *
     */

    /// @notice Emitted when the address of AllowanceTransfer is updated.
    /// @param oldAllowanceTransfer The address of the old AllowanceTransfer.
    /// @param newAllowanceTransfer The address of the new AllowanceTransfer.
    event SetAllowanceTransfer(address indexed oldAllowanceTransfer, address indexed newAllowanceTransfer);

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @notice Allow the L1GatewayRouter to spend `token` using Permit2 AllowanceTransfer.
    /// @param token The address of the ERC20 token to approve.
    /// @param amount The allowance amount to grant.
    /// @param expiration The timestamp at which the approval is no longer valid
    function allowRouterToTransfer(address token, uint160 amount, uint48 expiration) external;

    /**
     *
     * Restricted Functions *
     *
     */

    /// @notice Update the address of AllowanceTransfer contract.
    /// @dev This function should only be called by contract owner.
    /// @param _allowanceTransfer The address to update.
    function setAllowanceTransfer(address _allowanceTransfer) external;
}
