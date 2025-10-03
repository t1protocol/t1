// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract XyieldToken is ERC20 {
    address public minter;

    event MinterChanged(address indexed oldMinter, address indexed newMinter);

    error ZeroAddress();
    error InvalidMinter();
    error NotAuthorized();

    constructor(address _minter, string memory name, string memory symbol) ERC20(name, symbol) {
        if (_minter == address(0)) revert ZeroAddress();
        minter = _minter;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotAuthorized();
        _;
    }

    /// @notice Updates the minter address
    /// @param newMinter The new minter address
    function updateMinter(address newMinter) external onlyMinter {
        if (newMinter == address(0)) revert ZeroAddress();
        if (newMinter == minter) revert InvalidMinter();
        address oldMinter = minter;
        minter = newMinter;
        emit MinterChanged(oldMinter, newMinter);
    }

    /// @notice Mints new tokens to the specified address
    /// @param to The address to receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /// @dev The standard burn function is already public and allows any address to burn their own tokens,
    /// emitting a Transfer event to address(0) as the burn signal. Thus, no custom burn event is defined.
}
