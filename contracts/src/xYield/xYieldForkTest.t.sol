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
    EVault internal evaultArbitrumUsdc;
    xYieldVault internal xYield;

    address internal guardian = address(0xbeb);
    address internal alice = 0xB9B7402f36608D3D7c9Cb3d2b17075241b6ee43f;
    USDC internal usdcArbitrum = USDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address internal usdcMasterMinter = 0x8aFf09e2259cacbF4Fc4e3E53F3bf799EfEEab36;
    address internal usdcMinter = address(0x333);

    function setUp() public {
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC");
        uint256 arbitrumBlock = vm.envUint("ARBITRUM_BLOCK");
        vm.createSelectFork(arbitrumRpcUrl, arbitrumBlock);

        address evault_arbitrum_usdc_proxy_address = 0x0a1eCC5Fe8C9be3C809844fcBe615B46A869b899;

        evaultArbitrumUsdc = EVault(evault_arbitrum_usdc_proxy_address);

        xYield = new xYieldVault(
            IERC20(address(usdcArbitrum)), guardian, "xYield USDC", "xyUSDC", evault_arbitrum_usdc_proxy_address
        );
    }

    function testDepositToEulerVault() public {
        uint256 evaultUsdcBalanceBefore = usdcArbitrum.balanceOf(address(evaultArbitrumUsdc));
        uint256 aliceUsdcDepositAmount = 100e6;
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYield), type(uint256).max);
        uint256 aliceShares = xYield.deposit(aliceUsdcDepositAmount, alice);

        vm.stopPrank();

        uint256 aliceAssets = xYield.convertToAssets(aliceShares);
        assertGe(aliceAssets, aliceShares, "Alice assets to redeem are greater than her shares");

        uint256 evaultUsdcBalanceAfter = usdcArbitrum.balanceOf(address(evaultArbitrumUsdc));
        assertEq(
            evaultUsdcBalanceAfter,
            evaultUsdcBalanceBefore + aliceUsdcDepositAmount,
            "EVault should have received 100 USDC from deposit"
        );

        uint256 xYieldEvaultBalance = evaultArbitrumUsdc.balanceOf(address(xYield));
        assertGt(xYieldEvaultBalance, 0, "xYield vault should have received EVault shares");
    }

    function testWithdrawFromEulerVault() public {
        uint256 aliceUsdcDepositAmount = 100e6;

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYield), type(uint256).max);
        uint256 aliceShares = xYield.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 evaultUsdcBalanceBeforeWithdraw = usdcArbitrum.balanceOf(address(evaultArbitrumUsdc));
        uint256 aliceUsdcBalanceBeforeWithdraw = usdcArbitrum.balanceOf(alice);
        uint256 xYieldEvaultBalanceBefore = evaultArbitrumUsdc.balanceOf(address(xYield));

        uint256 withdrawAmount = 50e6;
        vm.startPrank(alice);
        uint256 sharesRedeemed = xYield.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 evaultUsdcBalanceAfterWithdraw = usdcArbitrum.balanceOf(address(evaultArbitrumUsdc));
        uint256 aliceUsdcBalanceAfterWithdraw = usdcArbitrum.balanceOf(alice);
        uint256 xYieldEvaultBalanceAfter = evaultArbitrumUsdc.balanceOf(address(xYield));

        assertEq(
            evaultUsdcBalanceAfterWithdraw,
            evaultUsdcBalanceBeforeWithdraw - withdrawAmount,
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
            "xYield vault should have fewer EVault shares after withdrawal"
        );
        assertLt(xYield.balanceOf(alice), aliceShares, "Alice should have fewer xYield shares after withdrawal");
        assertGt(sharesRedeemed, 0, "Shares redeemed should be greater than 0");
    }

    function testInterestAccrualIncreasesAssetValue() public {
        uint256 aliceUsdcDepositAmount = 100e6;

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYield), type(uint256).max);
        uint256 aliceShares = xYield.deposit(aliceUsdcDepositAmount, alice);
        vm.stopPrank();

        uint256 aliceAssetsBeforeInterest = xYield.convertToAssets(aliceShares);
        uint256 totalBorrowsBefore = evaultArbitrumUsdc.totalBorrows();

        vm.warp(block.timestamp + 365 days);

        uint256 aliceAssetsAfterInterest = xYield.convertToAssets(aliceShares);
        uint256 totalBorrowsAfter = evaultArbitrumUsdc.totalBorrows();

        console2.log("alice interest as percentage x 100:: ", (aliceAssetsAfterInterest - aliceAssetsBeforeInterest) * 10000 / aliceAssetsBeforeInterest);
        assertGt(aliceAssetsAfterInterest, aliceAssetsBeforeInterest, "Alice's assets should increase due to interest accrual when there are existing borrowers");
        assertGt(totalBorrowsAfter, totalBorrowsBefore, "Total borrows should increase due to interest accrual");
    }
}
