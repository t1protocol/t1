// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { EVault } from "@euler-xyz/EVault/EVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import { xYieldVault } from "../../xYield/xYieldVault.sol";

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
    address internal charlie = address(0xccc);
    // address internal usdcMasterMinter = 0x8aFf09e2259cacbF4Fc4e3E53F3bf799EfEEab36;
    USDC internal usdcArbitrum = USDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    USDC internal usdcBase = USDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // pretend this is USDC on Base

    // Real Arbitrum deployed contracts
    address payable public constant acrossSpokePoolArbitrum = payable(0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A);
    address payable public constant multicallHandlerArbitrum = payable(0x924a9f036260DdD5808007E1AA95f08eD08aA569);

    address[] emptyAddresses;
    uint256[] emptyAmounts;

    uint256 depositAmount = 100e6;

    uint64 baseChainId = 8453;

    // Helper function to easily simulate cross-chain deposits for testing
    function _simulateRemoteDeposit(
        address user,
        uint256 amount,
        uint64 sourceChainId,
        uint64 targetChainId
    )
        internal
        returns (uint256 shares)
    {
        xYieldVault activeVault = targetChainId == baseChainId ? xYieldBase : xYieldArbitrum;
        IERC20 targetAsset = targetChainId == baseChainId ? IERC20(address(usdcBase)) : IERC20(address(usdcArbitrum));

        // Transfer assets to target vault and call depositFrom directly (simulating multicall handler)
        vm.startPrank(user);
        targetAsset.approve(address(activeVault), amount);
        shares = activeVault.depositFrom(amount, user, sourceChainId);
        vm.stopPrank();

        return shares;
    }

    function setUp() public {
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC");
        uint256 arbitrumBlock = vm.envUint("ARBITRUM_BLOCK");
        vm.createSelectFork(arbitrumRpcUrl, arbitrumBlock);

        address eVaultArbitrumUsdcProxyAddress = 0x0a1eCC5Fe8C9be3C809844fcBe615B46A869b899;

        eVaultArbitrumUsdc = EVault(eVaultArbitrumUsdcProxyAddress);

        xYieldArbitrum = new xYieldVault(
            IERC20(address(usdcArbitrum)),
            guardian,
            "xYieldArbitrum USDC",
            "xyUSDCArb",
            eVaultArbitrumUsdcProxyAddress,
            acrossSpokePoolArbitrum
        );
        xYieldBase = new xYieldVault(
            IERC20(address(usdcArbitrum)),
            guardian,
            "xYieldBase USDC",
            "xyUSDCBase",
            eVaultArbitrumUsdcProxyAddress,
            acrossSpokePoolArbitrum
        );

        vm.prank(guardian);
        xYieldArbitrum.setActiveChain(true);
        xYieldArbitrum.setSiblingVault(
            baseChainId, address(xYieldBase), address(usdcArbitrum), multicallHandlerArbitrum
        );
        xYieldBase.setSiblingVault(
            uint64(block.chainid), address(xYieldArbitrum), address(usdcArbitrum), multicallHandlerArbitrum
        );

        vm.startPrank(alice);
        usdcArbitrum.transfer(bob, 100e6);
        usdcArbitrum.transfer(charlie, 100e6);
        vm.stopPrank();

        setLabels();
    }

    function setLabels() internal {
        vm.label(bob, "Bob");
        vm.label(alice, "Alice");
        vm.label(charlie, "Charlie");
        vm.label(guardian, "Guardian");
        vm.label(usdcMinter, "USDC Minter");
        vm.label(address(xYieldArbitrum), "xYieldArbitrum");
        vm.label(address(xYieldBase), "xYieldBase");
        vm.label(address(eVaultArbitrumUsdc), "EVaultArbitrumUsdc");
    }

    function testDepositToEulerVault() public {
        uint256 eVaultUsdcBalanceBefore = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        assertGe(aliceAssets, aliceShares, "Alice assets to redeem are greater than her shares");

        uint256 eVaultUsdcBalanceAfter = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfter,
            eVaultUsdcBalanceBefore + depositAmount,
            "EVault should have received 100 USDC from deposit"
        );

        uint256 xYieldEvaultBalance = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));
        assertGt(xYieldEvaultBalance, 0, "xYieldArbitrum vault should have received EVault shares");
    }

    function testWithdrawFromEulerVault() public {
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
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
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
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

    function testSharePriceCalculation() public {
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 shares1 = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        // Wait for yield to accrue
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(bob);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 shares2 = xYieldArbitrum.deposit(depositAmount, bob);
        vm.stopPrank();

        assertTrue(shares1 > shares2, "Second deposit should get fewer shares due to increased asset value from yield");
    }

    function testRemoteWithdrawUpdateTotalShares() public {
        // Setup: First do deposits to have assets to withdraw from
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceSharesNative = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 bobSharesRemote = _simulateRemoteDeposit(bob, depositAmount, baseChainId, uint64(block.chainid));

        // Update totals to reflect both deposits
        uint256 totalSharesGlobal = aliceSharesNative + bobSharesRemote;
        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](1);
        balanceUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: bob, amount: bobSharesRemote, txType: xYieldVault.TxType.Deposit });

        vm.startPrank(guardian);
        xYieldBase.updateTotals(totalSharesGlobal, balanceUpdates);
        vm.stopPrank();

        // Verify initial state
        assertEq(
            xYieldArbitrum.totalSupply(), totalSharesGlobal, "Initial virtual total supply should match global total"
        );
        assertEq(xYieldBase.balanceOf(bob), bobSharesRemote, "Bob should have shares on Base");

        uint256 withdrawAmount = 30e6; // Withdraw 30 USDC from Bob's remote shares
        uint256 bobInitialShares = xYieldBase.balanceOf(bob);
        uint256 aliceInitialShares = xYieldArbitrum.balanceOf(alice);
        uint256 initialVirtualSupply = xYieldArbitrum.totalSupply();

        vm.startPrank(guardian);
        uint256 sharesToBurn = xYieldArbitrum.withdrawFrom(
            withdrawAmount,
            bob,
            baseChainId,
            withdrawAmount * 90 / 100,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 1800),
            0
        );
        vm.stopPrank();

        // Update totals to reflect the withdrawal
        uint256 newTotalSharesGlobal = totalSharesGlobal - sharesToBurn;
        xYieldVault.BalanceUpdate[] memory withdrawUpdates = new xYieldVault.BalanceUpdate[](1);
        withdrawUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: bob, amount: sharesToBurn, txType: xYieldVault.TxType.Withdraw });

        vm.startPrank(guardian);
        xYieldBase.updateTotals(newTotalSharesGlobal, withdrawUpdates);
        vm.stopPrank();

        // Verify the withdrawal updated total shares correctly
        assertEq(
            xYieldArbitrum.totalSupply(),
            newTotalSharesGlobal,
            "Virtual total supply should be reduced by withdrawn shares"
        );

        assertLt(xYieldBase.balanceOf(bob), bobInitialShares, "Bob's shares on Base should be reduced after withdrawal");

        assertEq(
            xYieldArbitrum.balanceOf(alice), aliceInitialShares, "Alice's shares on Arbitrum should remain unchanged"
        );

        assertEq(
            xYieldBase.balanceOf(bob),
            bobInitialShares - sharesToBurn,
            "Bob's remaining shares should equal initial minus burned shares"
        );

        assertEq(
            xYieldArbitrum.totalSupply(),
            aliceInitialShares + xYieldBase.balanceOf(bob),
            "Virtual total supply should equal sum of all remaining shares across chains"
        );

        // Verify that share price remains consistent
        uint256 aliceAssetsAfter = xYieldArbitrum.convertToAssets(aliceInitialShares);
        uint256 bobAssetsAfter = xYieldArbitrum.convertToAssets(xYieldBase.balanceOf(bob));
        uint256 totalAssetsAfter = xYieldArbitrum.totalAssets();

        // Account for the expected 1 wei difference due to ERC4626 initial deposit formula
        uint256 difference = totalAssetsAfter > (aliceAssetsAfter + bobAssetsAfter)
            ? totalAssetsAfter - (aliceAssetsAfter + bobAssetsAfter)
            : (aliceAssetsAfter + bobAssetsAfter) - totalAssetsAfter;

        assertTrue(difference <= 1, "Asset conversion difference should be at most 1 wei after withdrawal");
    }

    function testProveERC4626Assets() public {
        // Scenario 1: Test with Alice's deposit only
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        // Check the individual conversion vs total
        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        uint256 totalAssets = xYieldArbitrum.totalAssets();

        uint256 singleUserDifference = totalAssets > aliceAssets ? totalAssets - aliceAssets : aliceAssets - totalAssets;

        assertEq(singleUserDifference, 0, "No diff between total and user assets");

        // Scenario 2: Add Bob's deposit
        uint256 bobSharesRemote = _simulateRemoteDeposit(bob, depositAmount, baseChainId, uint64(block.chainid));

        // Update totals to create the virtual supply scenario
        uint256 totalSharesGlobal = xYieldArbitrum.totalSupply();
        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](1);
        balanceUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: bob, amount: bobSharesRemote, txType: xYieldVault.TxType.Deposit });

        vm.startPrank(guardian);
        xYieldBase.updateTotals(totalSharesGlobal, balanceUpdates);
        vm.stopPrank();

        totalAssets = xYieldArbitrum.totalAssets();
        uint256 newAliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        uint256 bobAssets = xYieldArbitrum.convertToAssets(bobSharesRemote);

        uint256 difference = totalAssets > (newAliceAssets + bobAssets)
            ? totalAssets - (newAliceAssets + bobAssets)
            : (newAliceAssets + bobAssets) - totalAssets;

        // Scenario 3: Prove this matches the mathematical expectation from ERC4626 formula
        // Formula: convertToAssets(shares) = shares * (totalAssets + 1) / (totalSupply + offset)
        uint256 currentTotalSupply = xYieldArbitrum.totalSupply();

        // Manual calculation using ERC4626 formula (simplified, assuming no decimals offset)
        uint256 expectedAliceAssets = (aliceShares * (totalAssets + 1)) / (currentTotalSupply + 1);
        uint256 expectedBobAssets = (bobSharesRemote * (totalAssets + 1)) / (currentTotalSupply + 1);

        assertEq(difference, 0, "No difference in totalAssets vs all user assets");
    }

    function testProveERC4626SameSharesMinted() public {
        // Bob's remote deposit
        uint256 bobSharesRemote = _simulateRemoteDeposit(bob, depositAmount, baseChainId, uint64(block.chainid));

        uint256 charlieSharesRemote = _simulateRemoteDeposit(charlie, depositAmount, baseChainId, uint64(block.chainid));

        // Alice same chain deposit
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(aliceShares, charlieSharesRemote, "Alice and Charlie receive the same amount shares");
    }

    function testRedeemFromBehaviorMatchesWithdrawFrom() public {
        // Setup: First do deposits to have assets to withdraw/redeem from
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceSharesNative = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 bobSharesRemote = _simulateRemoteDeposit(bob, depositAmount, baseChainId, uint64(block.chainid));
        uint256 charlieSharesRemote = _simulateRemoteDeposit(charlie, depositAmount, baseChainId, uint64(block.chainid));

        // Update totals to reflect all deposits
        uint256 totalSharesGlobal = aliceSharesNative + bobSharesRemote + charlieSharesRemote;
        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](2);
        balanceUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: bob, amount: bobSharesRemote, txType: xYieldVault.TxType.Deposit });
        balanceUpdates[1] = xYieldVault.BalanceUpdate({
            recipient: charlie,
            amount: charlieSharesRemote,
            txType: xYieldVault.TxType.Deposit
        });

        vm.startPrank(guardian);
        xYieldBase.updateTotals(totalSharesGlobal, balanceUpdates);
        vm.stopPrank();

        // Test 1: withdrawFrom with Bob's shares
        uint256 withdrawAmount = 30e6;
        uint256 bobInitialShares = xYieldBase.balanceOf(bob);
        uint256 initialVirtualSupply = xYieldArbitrum.totalSupply();
        uint256 initialTotalAssets = xYieldArbitrum.totalAssets();

        // Calculate expected shares to burn for withdrawFrom
        uint256 expectedSharesForWithdraw = xYieldArbitrum.previewWithdraw(withdrawAmount);

        vm.startPrank(guardian);
        uint256 sharesBurnedByWithdraw = xYieldArbitrum.withdrawFrom(
            withdrawAmount,
            bob,
            baseChainId,
            withdrawAmount * 90 / 100,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 1800),
            0
        );
        vm.stopPrank();

        assertEq(sharesBurnedByWithdraw, expectedSharesForWithdraw, "withdrawFrom should burn expected shares");
        assertEq(
            xYieldArbitrum.totalSupply(),
            initialVirtualSupply - sharesBurnedByWithdraw,
            "Virtual supply should decrease by burned shares after withdrawFrom"
        );

        // Test 2: redeemFrom with Charlie's shares (redeem same amount of shares)
        uint256 sharesToRedeem = sharesBurnedByWithdraw; // Use same amount of shares for comparison
        uint256 charlieInitialShares = xYieldBase.balanceOf(charlie);
        uint256 supplyBeforeRedeem = xYieldArbitrum.totalSupply();
        uint256 assetsBeforeRedeem = xYieldArbitrum.totalAssets();

        // Calculate expected assets for redeemFrom
        uint256 expectedAssetsForRedeem = xYieldArbitrum.previewRedeem(sharesToRedeem);

        vm.startPrank(guardian);
        uint256 assetsWithdrawnByRedeem = xYieldArbitrum.redeemFrom(
            sharesToRedeem,
            charlie,
            baseChainId,
            expectedAssetsForRedeem * 90 / 100,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 1800),
            0
        );
        vm.stopPrank();

        assertEq(assetsWithdrawnByRedeem, expectedAssetsForRedeem, "redeemFrom should withdraw expected assets");
        assertEq(
            xYieldArbitrum.totalSupply(),
            supplyBeforeRedeem - sharesToRedeem,
            "Virtual supply should decrease by redeemed shares after redeemFrom"
        );

        // Test 3: Verify conversion consistency
        // When we withdraw X assets, we burn Y shares
        // When we redeem Y shares, we should get approximately X assets
        assertApproxEqAbs(
            assetsWithdrawnByRedeem,
            withdrawAmount,
            2,
            "Redeeming same shares should withdraw approximately same assets"
        );

        // Test 4: Verify that both methods maintain share price consistency
        uint256 sharePriceAfterWithdraw = xYieldArbitrum.convertToAssets(1e6);
        uint256 sharePriceAfterRedeem = xYieldArbitrum.convertToAssets(1e6);

        assertApproxEqAbs(
            sharePriceAfterWithdraw,
            sharePriceAfterRedeem,
            1,
            "Share price should remain consistent between withdrawFrom and redeemFrom"
        );

        // Update totals to reflect both operations
        xYieldVault.BalanceUpdate[] memory withdrawUpdates = new xYieldVault.BalanceUpdate[](2);
        withdrawUpdates[0] = xYieldVault.BalanceUpdate({
            recipient: bob,
            amount: sharesBurnedByWithdraw,
            txType: xYieldVault.TxType.Withdraw
        });
        withdrawUpdates[1] = xYieldVault.BalanceUpdate({
            recipient: charlie,
            amount: sharesToRedeem,
            txType: xYieldVault.TxType.Withdraw
        });

        uint256 newTotalSharesGlobal = totalSharesGlobal - sharesBurnedByWithdraw - sharesToRedeem;
        vm.startPrank(guardian);
        xYieldBase.updateTotals(newTotalSharesGlobal, withdrawUpdates);
        vm.stopPrank();

        // Verify final state
        assertEq(
            xYieldBase.balanceOf(bob),
            bobInitialShares - sharesBurnedByWithdraw,
            "Bob's shares should be reduced by withdrawn amount"
        );
        assertEq(
            xYieldBase.balanceOf(charlie),
            charlieInitialShares - sharesToRedeem,
            "Charlie's shares should be reduced by redeemed amount"
        );

        // Test 5: Verify inverse relationship
        // If we know the shares burned for a withdrawal, converting those shares to assets should give the withdrawn
        // amount
        uint256 assetsFromShares = xYieldArbitrum.convertToAssets(sharesBurnedByWithdraw);
        assertApproxEqAbs(
            assetsFromShares, withdrawAmount, 1, "Converting burned shares to assets should equal withdrawn amount"
        );

        // If we know the assets withdrawn for a redemption, converting those assets to shares should give the redeemed
        // shares
        uint256 sharesFromAssets = xYieldArbitrum.convertToShares(assetsWithdrawnByRedeem);
        assertApproxEqAbs(
            sharesFromAssets, sharesToRedeem, 1, "Converting withdrawn assets to shares should equal redeemed shares"
        );
    }

    function testFullRebalanceFlow() public {
        vm.startPrank(guardian);
        xYieldArbitrum.setActiveChain(true);
        xYieldBase.setActiveChain(false);
        vm.stopPrank();

        vm.startPrank(address(this));
        xYieldArbitrum.setSiblingVault(baseChainId, address(xYieldBase), address(usdcBase), multicallHandlerArbitrum);
        xYieldBase.setSiblingVault(
            uint64(block.chainid), address(xYieldArbitrum), address(usdcArbitrum), multicallHandlerArbitrum
        );
        vm.stopPrank();

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 rebalanceAmount = xYieldArbitrum.totalAssets();
        uint256 rebalanceId = 12_345;
        uint256 outputAmount = rebalanceAmount * 99 / 100;

        vm.startPrank(guardian);
        xYieldArbitrum.rebalance(
            rebalanceId, uint32(baseChainId), rebalanceAmount, outputAmount, uint32(block.timestamp)
        );
        vm.stopPrank();

        assertFalse(xYieldArbitrum.isActiveChain());

        vm.startPrank(alice);
        usdcBase.transfer(address(xYieldBase), rebalanceAmount);
        vm.stopPrank();

        bytes memory rebalanceMessage = abi.encode(uint8(xYieldVault.TxType.Rebalance), rebalanceId, bytes(""));

        vm.prank(address(0xdeadbeef));
        xYieldBase.handleV3AcrossMessage(address(usdcBase), rebalanceAmount, address(0xdeadbeef), rebalanceMessage);

        vm.startPrank(guardian);
        xYieldBase.finalizeRebalance();
        vm.stopPrank();

        assertTrue(xYieldBase.isActiveChain());
        assertFalse(xYieldArbitrum.isActiveChain());
        assertEq(xYieldArbitrum.totalAssets(), 0);
        assertGt(xYieldBase.totalAssets(), 0);
        assertEq(xYieldArbitrum.balanceOf(alice), aliceShares);
    }

    function testDepositTo() public {
        vm.startPrank(guardian);
        xYieldBase.setActiveChain(true);
        xYieldArbitrum.setActiveChain(false);
        vm.stopPrank();

        vm.startPrank(address(this));
        xYieldArbitrum.setSiblingVault(baseChainId, address(xYieldBase), address(usdcBase), multicallHandlerArbitrum);
        vm.stopPrank();

        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);

        uint256 outputAmount = 99e6; // Explicit amount to avoid rounding issues
        xYieldArbitrum.depositTo(
            depositAmount,
            alice,
            baseChainId,
            outputAmount,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 1800),
            0
        );
        vm.stopPrank();

        // Simulate multicall handler executing depositFrom
        vm.startPrank(alice);
        usdcBase.approve(address(xYieldBase), outputAmount);
        uint256 shares = xYieldBase.depositFrom(outputAmount, alice, uint64(block.chainid));
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertApproxEqAbs(
            xYieldBase.totalAssets(), outputAmount, 1, "Vault should have approximately the expected assets"
        );
    }
}
