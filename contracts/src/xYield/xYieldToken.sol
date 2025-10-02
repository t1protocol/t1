// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract xYieldToken is ERC20 {
    address public immutable minter;

    constructor(address _minter, string memory name, string memory symbol) ERC20(name, symbol) {
        require(_minter != address(0), "Minter address cannot be zero");
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller is not the minter");
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /// @dev The standard burn function is already public and allows any holder to burn their own tokens,
    /// emitting a Transfer event to address(0) as the burn signal.
}