// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract xYieldToken is ERC20 {
    address public minter;

    // Event to log minter address changes
    event MinterChanged(address indexed oldMinter, address indexed newMinter);

    constructor(address _minter, string memory name, string memory symbol) ERC20(name, symbol) {
        require(_minter != address(0), "Minter address cannot be zero");
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller is not the minter");
        _;
    }

    /// @notice Updates the minter address
    /// @param newMinter The new minter address
    function updateMinter(address newMinter) external onlyMinter {
        require(newMinter != address(0), "New minter address cannot be zero");
        require(newMinter != minter, "New minter address must be different");
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
