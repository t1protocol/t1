// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { xYieldVault } from "./xYieldVault.sol";
import { MockYieldProtocol } from "./MockYieldProtocol.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract xYieldTest is Test {
    xYieldVault public vault;
    MockYieldProtocol public yieldProtocol;
    MockUSDC public usdc;

    address public guardian = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 public constant INITIAL_DEPOSIT = 1000 * 10**18;

    function setUp() public {
        usdc = new MockUSDC();
        yieldProtocol = new MockYieldProtocol(IERC20(address(usdc)), "Mock Yield USDC", "mUSDC");

        vault = new xYieldVault(
            IERC20(address(usdc)),
            guardian,
            "xYield USDC",
            "xyUSDC",
            address(yieldProtocol)
        );

        usdc.mint(user1, INITIAL_DEPOSIT);
        usdc.mint(user2, INITIAL_DEPOSIT);

        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 * 10**18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(usdc.balanceOf(user1), INITIAL_DEPOSIT - depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 50 * 10**18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialBalance = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);

        assertEq(usdc.balanceOf(user1), initialBalance + withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
    }

    function testSharePriceCalculation() public {
        uint256 depositAmount = 100 * 10**18;

        vm.prank(user1);
        uint256 shares1 = vault.deposit(depositAmount, user1);

        vm.warp(block.timestamp + 365 days);

        vm.prank(guardian);
        vault.updateSharePrice(110 * 10**18); // Simulate 10% yield

        vm.prank(user2);
        uint256 shares2 = vault.deposit(depositAmount, user2);

        assertTrue(shares1 > shares2, "Second deposit should get fewer shares due to increased asset value");
    }

    function testActiveChainBehavior() public {
        uint256 depositAmount = 100 * 10**18;

        assertTrue(vault.isActiveChain());

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        assertTrue(yieldProtocol.balanceOf(address(vault)) > 0, "Yield protocol should have received deposit");
    }

    function testInactiveChainBehavior() public {
        uint256 depositAmount = 100 * 10**18;

        vm.prank(guardian);
        vault.setActiveChain(false);

        assertFalse(vault.isActiveChain());

        vm.expectRevert(abi.encodeWithSelector(xYieldVault.DepositOnInactiveChain.selector));
        vm.prank(user1);
        vault.deposit(depositAmount, user1);
    }

    function testGuardianFunctions() public {
        uint256 newVirtualAssets = 200 * 10**18;

        vm.prank(guardian);
        vault.updateSharePrice(newVirtualAssets);

        assertEq(vault.virtualTotalAssets(), newVirtualAssets);

        vm.prank(guardian);
        vault.setActiveChain(false);

        assertFalse(vault.isActiveChain());
    }

    function testRevertOnUnauthorizedAccess() public {
        vm.expectRevert(abi.encodeWithSelector(xYieldVault.NotGuardian.selector));
        vm.prank(user1);
        vault.updateSharePrice(100);

        vm.expectRevert(abi.encodeWithSelector(xYieldVault.NotGuardian.selector));
        vm.prank(user1);
        vault.setActiveChain(false);
    }

    function testZeroAmountDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(xYieldVault.ZeroAmount.selector));
        vm.prank(user1);
        vault.deposit(0, user1);
    }

    function testPauseUnpause() public {
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(user1);
        vault.deposit(100, user1);

        vault.unpause();

        vm.prank(user1);
        vault.deposit(100, user1);
    }
}