// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { EVault } from "@euler-xyz/EVault/EVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import { xYieldVault } from "./xYieldVault.sol";

abstract contract USDC is ERC20PresetMinterPauser {
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool) { }
}

contract xYieldForkTest is Test {
    EVault internal eVaultArbitrumUsdc;
    xYieldVault internal xYieldArbitrum;
    // For simplicity in basic unit testing we will pretend that this contract is deployed on Base
    xYieldVault internal xYieldBase;

    address internal guardian = address(0xbeb);
    address internal usdcMinter = address(0x333);
    address internal alice = 0xB9B7402f36608D3D7c9Cb3d2b17075241b6ee43f;
    address internal bob = address(0xbbb);
    // address internal usdcMasterMinter = 0x8aFf09e2259cacbF4Fc4e3E53F3bf799EfEEab36;
    USDC internal usdcArbitrum = USDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public {
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC");
        uint256 arbitrumBlock = vm.envUint("ARBITRUM_BLOCK");
        vm.createSelectFork(arbitrumRpcUrl, arbitrumBlock);

        address eVaultArbitrumUsdcProxyAddress = 0x0a1eCC5Fe8C9be3C809844fcBe615B46A869b899;

        eVaultArbitrumUsdc = EVault(eVaultArbitrumUsdcProxyAddress);

        xYieldArbitrum = new xYieldVault(
            IERC20(address(usdcArbitrum)), guardian, "xYieldArbitrum USDC", "xyUSDCArb", eVaultArbitrumUsdcProxyAddress
        );
        xYieldBase = new xYieldVault(
            IERC20(address(usdcArbitrum)), guardian, "xYieldBase USDC", "xyUSDCBase", eVaultArbitrumUsdcProxyAddress
        );

        vm.prank(guardian);
        xYieldArbitrum.setActiveChain(true);

        vm.startPrank(alice);
        usdcArbitrum.transfer(bob, 100e6);
        vm.stopPrank();
    }

    function testDepositToEulerVault() public {
        uint256 eVaultUsdcBalanceBefore = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceUsdcDepositAmount = 100e6;
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        assertGe(aliceAssets, aliceShares, "Alice assets to redeem are greater than her shares");

        uint256 eVaultUsdcBalanceAfter = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfter,
            eVaultUsdcBalanceBefore + aliceUsdcDepositAmount,
            "EVault should have received 100 USDC from deposit"
        );

        uint256 xYieldEvaultBalance = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));
        assertGt(xYieldEvaultBalance, 0, "xYieldArbitrum vault should have received EVault shares");
    }

    function testWithdrawFromEulerVault() public {
        uint256 aliceUsdcDepositAmount = 100e6;

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 eVaultUsdcBalanceBeforeWithdraw = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceUsdcBalanceBeforeWithdraw = usdcArbitrum.balanceOf(alice);
        uint256 xYieldEvaultBalanceBefore = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));

        uint256 withdrawAmount = 50e6;
        vm.startPrank(alice);
        uint256 sharesRedeemed = xYieldArbitrum.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 eVaultUsdcBalanceAfterWithdraw = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceUsdcBalanceAfterWithdraw = usdcArbitrum.balanceOf(alice);
        uint256 xYieldEvaultBalanceAfter = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));

        assertEq(
            eVaultUsdcBalanceAfterWithdraw,
            eVaultUsdcBalanceBeforeWithdraw - withdrawAmount,
            "EVault should have 50 USDC less after withdrawal"
        );
        assertEq(
            aliceUsdcBalanceAfterWithdraw,
            aliceUsdcBalanceBeforeWithdraw + withdrawAmount,
            "Alice should have received 50 USDC from withdrawal"
        );
        assertLt(
            xYieldEvaultBalanceAfter,
            xYieldEvaultBalanceBefore,
            "xYieldArbitrum vault should have fewer EVault shares after withdrawal"
        );
        assertLt(
            xYieldArbitrum.balanceOf(alice),
            aliceShares,
            "Alice should have fewer xYieldArbitrum shares after withdrawal"
        );
        assertGt(sharesRedeemed, 0, "Shares redeemed should be greater than 0");
    }

    function testInterestAccrualIncreasesAssetValue() public {
        uint256 aliceUsdcDepositAmount = 100e6;

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 aliceAssetsBeforeInterest = xYieldArbitrum.convertToAssets(aliceShares);
        uint256 totalBorrowsBefore = eVaultArbitrumUsdc.totalBorrows();

        vm.warp(block.timestamp + 365 days);

        uint256 aliceAssetsAfterInterest = xYieldArbitrum.convertToAssets(aliceShares);
        uint256 totalBorrowsAfter = eVaultArbitrumUsdc.totalBorrows();

        console2.log(
            "alice interest as percentage x 100:: ",
            (aliceAssetsAfterInterest - aliceAssetsBeforeInterest) * 10_000 / aliceAssetsBeforeInterest
        );
        assertGt(
            aliceAssetsAfterInterest,
            aliceAssetsBeforeInterest,
            "Alice's assets should increase due to interest accrual when there are existing borrowers"
        );
        assertGt(totalBorrowsAfter, totalBorrowsBefore, "Total borrows should increase due to interest accrual");
    }

    function testRemoteDeposit() public {
        uint256 eVaultUsdcBalanceBefore = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceXyusdBalanceBefore = xYieldArbitrum.balanceOf(alice);
        // initiate deposit from A
        // mock bridge from A to B
        // assets land on B, but share price is not yet updated. If no distinction between total assets before
        // and after share price is updated, older shareholders could withdraw more than they are entitled to
        // (since share price has not caught up with underlying assets). we want to instead always base the shares on a
        // virtual total assets
        // we need to ensure that local deposits use that virtual amount (amount pre remote deposit) until share price
        // is updated
        uint256 aliceUsdcDepositAmount = 100e6;

        vm.startPrank(alice); // acting as filler for her own intent
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.depositFrom(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 aliceXyusdBalanceAfter = xYieldArbitrum.balanceOf(alice);

        assertEq(aliceXyusdBalanceBefore, aliceXyusdBalanceAfter, "Alice was not minted any share tokens on this chain");
        assertEq(0, aliceXyusdBalanceAfter, "Alice does not own any share tokens");

        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        assertGe(aliceAssets, aliceShares, "Alice assets to redeem are greater than her shares");

        uint256 eVaultUsdcBalanceAfter = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfter,
            eVaultUsdcBalanceBefore + aliceUsdcDepositAmount,
            "EVault should have received 100 USDC from deposit"
        );

        uint256 xYieldEvaultBalance = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));
        assertGt(xYieldEvaultBalance, 0, "xYieldArbitrum vault should have received EVault shares");
    }

    function testRemoteDepositUpdateTotalShares() public {
        // native chain deposit
        uint256 eVaultUsdcBalanceBeforeDeposit0 = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceUsdcDepositAmount = 100e6;
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceSharesNative = xYieldArbitrum.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 bobXyusdBalanceBefore = xYieldArbitrum.balanceOf(bob);

        // remote chain deposit
        vm.startPrank(bob); // acting as filler for his own intent
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 bobSharesRemote = xYieldArbitrum.depositFrom(aliceUsdcDepositAmount, bob);
        vm.stopPrank();

        uint256 bobXyusdBalanceAfter = xYieldArbitrum.balanceOf(bob);

        assertEq(bobXyusdBalanceBefore, bobXyusdBalanceAfter, "Bob was not minted any share tokens on this chain");
        assertEq(0, bobXyusdBalanceAfter, "Bob does not own any share tokens on this chain");

        uint256 eVaultUsdcBalanceAfterDeposit1 = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfterDeposit1,
            eVaultUsdcBalanceBeforeDeposit0 + aliceUsdcDepositAmount * 2,
            "EVault should have received 100 USDC from deposit"
        );

        assertGt(aliceSharesNative, bobSharesRemote, "Alice is minted more shares than Bob");

        // TODO - mint bobSharesRemote to bob on remote chain
        // TODO - update total shares on remote and this chain
    }
}
