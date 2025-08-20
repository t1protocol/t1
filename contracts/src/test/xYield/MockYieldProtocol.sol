// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockYieldProtocol is ERC20 {
    IERC20 public immutable underlying;

    uint256 public mockYieldRate = 1050; // 5% APY represented as 1050/1000
    uint256 public lastYieldUpdate;
    uint256 public accumulatedYield;

    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public lastUserUpdate;

    error ZeroAssets();
    error InsufficientBalance();

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event YieldAccrued(uint256 amount);

    constructor(IERC20 _underlying, string memory name, string memory symbol) ERC20(name, symbol) {
        underlying = _underlying;
        lastYieldUpdate = block.timestamp;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        _accrueYield();

        underlying.transferFrom(msg.sender, address(this), assets);

        shares = totalSupply() == 0 ? assets : (assets * totalSupply()) / totalAssets();

        userDeposits[receiver] += assets;
        lastUserUpdate[receiver] = block.timestamp;

        _mint(receiver, shares);

        emit Deposited(receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        _accrueYield();

        shares = (assets * totalSupply()) / totalAssets();
        if (shares > balanceOf(owner)) revert InsufficientBalance();

        _burn(owner, shares);
        underlying.transfer(receiver, assets);

        if (userDeposits[owner] >= assets) {
            userDeposits[owner] -= assets;
        } else {
            userDeposits[owner] = 0;
        }

        emit Withdrawn(owner, assets, shares);
    }

    function totalAssets() public view returns (uint256) {
        uint256 timePassed = block.timestamp - lastYieldUpdate;
        uint256 pendingYield = (underlying.balanceOf(address(this)) * mockYieldRate * timePassed) / (1000 * 365 days);
        return underlying.balanceOf(address(this)) + accumulatedYield + pendingYield;
    }

    function _accrueYield() internal {
        uint256 timePassed = block.timestamp - lastYieldUpdate;
        if (timePassed > 0) {
            uint256 newYield = (underlying.balanceOf(address(this)) * mockYieldRate * timePassed) / (1000 * 365 days);
            accumulatedYield += newYield;
            lastYieldUpdate = block.timestamp;

            if (newYield > 0) {
                emit YieldAccrued(newYield);
            }
        }
    }

    function setYieldRate(uint256 newRate) external {
        _accrueYield();
        mockYieldRate = newRate;
    }

    function simulateYield(uint256 amount) external {
        accumulatedYield += amount;
        emit YieldAccrued(amount);
    }
}
