// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { xYieldVault } from "../../xYield/xYieldVault.sol";
import { MockYieldProtocol } from "./MockYieldProtocol.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Mock4626 is ERC4626 {
    bool on;

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        bool _on
    )
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        on = _on;
    }
}

contract xYieldTest is Test {
    xYieldVault public vault;
    Mock4626 public yieldProtocol; // mocking a vault
    MockUSDC public usdc;

    address public guardian = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 public constant INITIAL_DEPOSIT = 1000 * 10 ** 18;

    address[] emptyAddresses;
    uint256[] emptyAmounts;

    function setUp() public {
        usdc = new MockUSDC();
        yieldProtocol = new Mock4626(IERC20(address(usdc)), "Euler USDC", "eUSDC", true);

        vault = new xYieldVault(IERC20(address(usdc)), guardian, "xYield USDC", "xyUSDC", address(yieldProtocol));

        vm.prank(guardian);
        vault.setActiveChain(true);

        usdc.mint(user1, INITIAL_DEPOSIT);
        usdc.mint(user2, INITIAL_DEPOSIT);

        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testDirectDeposit() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(vault.balanceOf(user1), shares, "shares balance of user1");
        assertEq(vault.totalSupply(), shares, "total supply");
        assertEq(vault.totalAssets(), depositAmount, "total assets");
        assertEq(usdc.balanceOf(user1), INITIAL_DEPOSIT - depositAmount, "usdc balance of user1");
    }

    function testDirectWithdraw() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialBalance = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);

        assertEq(usdc.balanceOf(user1), initialBalance + withdrawAmount, "usdc balance of user1");
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount, "total assets");
    }

    function testActiveChainBehavior() public {
        uint256 depositAmount = 100 * 10 ** 18;

        assertTrue(vault.isActiveChain());

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        assertTrue(yieldProtocol.balanceOf(address(vault)) > 0, "Yield protocol should have received deposit");
    }

    function testInactiveChainBehavior() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(guardian);
        vault.setActiveChain(false);

        assertFalse(vault.isActiveChain());

        vm.expectRevert(abi.encodeWithSelector(xYieldVault.DepositOnInactiveChain.selector));
        vm.prank(user1);
        vault.deposit(depositAmount, user1);
    }

    function testGuardianFunctions() public {
        uint256 newVirtualTotalSupply = 200 * 10 ** 18;
        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 100 * 10 ** 18;

        vm.prank(guardian);
        vault.updateTotals(newVirtualTotalSupply, addresses, amounts);

        assertEq(vault.virtualTotalSupply(), newVirtualTotalSupply, "virtual total supply");

        vm.prank(guardian);
        vault.setActiveChain(false);

        assertFalse(vault.isActiveChain(), "is active chain");
    }

    function testRevertOnUnauthorizedAccess() public {
        vm.expectRevert(abi.encodeWithSelector(xYieldVault.NotGuardian.selector));
        vm.prank(user1);
        vault.updateTotals(100, emptyAddresses, emptyAmounts);

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

    function testSiblingVaultsRevert() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(xYieldVault.InvalidChain.selector));
        vault.depositFrom(depositAmount, user1, 1);

        vm.prank(vault.owner());
        vault.setSiblingVault(1, address(0x4));

        vm.prank(user1);
        vault.depositFrom(depositAmount, user1, 1);
    }
}
