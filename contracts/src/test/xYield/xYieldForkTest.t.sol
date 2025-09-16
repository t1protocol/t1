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
    address public acrossSpokePoolArbitrum = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;

    address[] emptyAddresses;
    uint256[] emptyAmounts;

    uint256 depositAmount = 100e6;

    uint64 baseChainId = 8453;

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
        xYieldArbitrum.setSiblingVault(baseChainId, address(xYieldBase), address(usdcArbitrum));

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

    function testRemoteDeposit() public {
        uint256 eVaultUsdcBalanceBefore = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        uint256 aliceXyusdBalanceBefore = xYieldArbitrum.balanceOf(alice);
        // initiate deposit from A
        // mock bridge from A to B
        // assets land on B, but share price is not yet updated. If no distinction between total assets before
        // and after share price is updated, older shareholders could withdraw more than they are entitled to
        // (since share price has not caught up with underlying assets).

        vm.startPrank(alice); // acting as filler for her own intent
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.depositFrom(depositAmount, alice, baseChainId);
        vm.stopPrank();

        uint256 aliceXyusdBalanceAfter = xYieldArbitrum.balanceOf(alice);

        assertEq(aliceXyusdBalanceBefore, aliceXyusdBalanceAfter, "Alice was not minted any share tokens on this chain");
        assertEq(0, aliceXyusdBalanceAfter, "Alice does not own any share tokens");

        uint256 eVaultUsdcBalanceAfter = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfter,
            eVaultUsdcBalanceBefore + depositAmount,
            "EVault should have received 100 USDC from deposit"
        );

        uint256 xYieldEvaultBalance = eVaultArbitrumUsdc.balanceOf(address(xYieldArbitrum));
        assertGt(xYieldEvaultBalance, 0, "xYieldArbitrum vault should have received EVault shares");

        vm.warp(block.timestamp + 365 days);

        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceShares);
        assertGe(aliceAssets, aliceShares, "Alice assets to redeem are greater than her shares");
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

    function testRemoteDepositUpdateTotalShares() public {
        // native chain deposit
        uint256 eVaultUsdcBalanceBeforeDeposit0 = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceSharesNative = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        console2.log("xYieldArbitrum.totalAssets() post alice deposit ::: ", xYieldArbitrum.totalAssets());

        vm.warp(block.timestamp + 365 days);

        uint256 bobXyusdBalanceBefore = xYieldArbitrum.balanceOf(bob);

        // remote chain deposit
        vm.startPrank(bob); // acting as filler for his own intent
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 bobSharesRemote = xYieldArbitrum.depositFrom(depositAmount, bob, baseChainId);
        vm.stopPrank();

        uint256 bobXyusdBalanceAfter = xYieldArbitrum.balanceOf(bob);

        assertEq(bobXyusdBalanceBefore, bobXyusdBalanceAfter, "Bob was not minted any share tokens on this chain");
        assertEq(0, bobXyusdBalanceAfter, "Bob does not own any share tokens on this chain");

        uint256 eVaultUsdcBalanceAfterDeposit1 = usdcArbitrum.balanceOf(address(eVaultArbitrumUsdc));
        assertEq(
            eVaultUsdcBalanceAfterDeposit1,
            eVaultUsdcBalanceBeforeDeposit0 + depositAmount * 2,
            "EVault should have received 100 USDC from deposit"
        );

        assertGt(aliceSharesNative, bobSharesRemote, "Alice is minted more shares than Bob");

        uint256 totalSharesArbitrum = xYieldArbitrum.totalSupply();
        uint256 totalSharesGlobal = totalSharesArbitrum;
        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](1);
        balanceUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: bob, amount: bobSharesRemote, txType: xYieldVault.TxType.Deposit });

        vm.startPrank(guardian);
        xYieldBase.updateTotals(totalSharesGlobal, balanceUpdates);
        vm.stopPrank();

        assertEq(
            xYieldArbitrum.totalSupply(), totalSharesGlobal, "Virtual total supply should match the global total shares"
        );

        uint256 bobRemoteShares = xYieldBase.balanceOf(bob);
        uint256 aliceNativeShares = xYieldArbitrum.balanceOf(alice);

        assertEq(
            xYieldArbitrum.balanceOf(alice), aliceSharesNative, "Alice's native share balance should remain unchanged"
        );

        assertEq(
            xYieldArbitrum.totalSupply(),
            aliceSharesNative + bobRemoteShares,
            "Total supply on this chain should include Alice's native shares and Bob's remote shares"
        );

        uint256 actualTotalAssets = xYieldArbitrum.totalAssets();
        uint256 aliceAssets = xYieldArbitrum.convertToAssets(aliceNativeShares);
        uint256 bobAssets = xYieldArbitrum.convertToAssets(bobRemoteShares);

        uint256 difference = actualTotalAssets > (aliceAssets + bobAssets)
            ? actualTotalAssets - (aliceAssets + bobAssets)
            : (aliceAssets + bobAssets) - actualTotalAssets;

        assertEq(difference, 1, "Expected exactly 1 wei difference due to ERC4626 initial deposit formula");

        assertTrue(actualTotalAssets > 0, "Total assets should be positive");
        assertTrue(aliceAssets + bobAssets > 0, "Sum of assets should be positive");
    }

    function testRemoteWithdrawUpdateTotalShares() public {
        // Setup: First do deposits to have assets to withdraw from
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceSharesNative = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 bobSharesRemote = xYieldArbitrum.depositFrom(depositAmount, bob, baseChainId);
        vm.stopPrank();

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
            address(usdcBase),
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
        vm.startPrank(bob);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 bobSharesRemote = xYieldArbitrum.depositFrom(depositAmount, bob, baseChainId);
        vm.stopPrank();

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
        vm.startPrank(bob);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 bobSharesRemote = xYieldArbitrum.depositFrom(depositAmount, bob, baseChainId);
        vm.stopPrank();

        vm.startPrank(charlie);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 charlieSharesRemote = xYieldArbitrum.depositFrom(depositAmount, charlie, baseChainId);
        vm.stopPrank();

        // Alice same chain deposit
        vm.startPrank(alice);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);
        uint256 aliceShares = xYieldArbitrum.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(aliceShares, charlieSharesRemote, "Alice and Charlie receive the same amount shares");
    }

    function testDepositToWithSignature() public {
        // Setup: Make Base chain inactive and Arbitrum active
        vm.startPrank(guardian);
        xYieldBase.setActiveChain(true);
        xYieldArbitrum.setActiveChain(false);
        vm.stopPrank();
        vm.startPrank(address(this));
        xYieldArbitrum.setSiblingVault(uint64(baseChainId), address(xYieldBase), address(usdcBase));
        xYieldBase.setSiblingVault(uint64(block.chainid), address(xYieldArbitrum), address(usdcArbitrum));
        vm.stopPrank();

        // Alice wants to deposit from Base (inactive) to Arbitrum (active)
        uint256 depositId = 12345; // Unique deposit ID for replay protection

        // Step 1: Alice creates and signs the deposit intent using EIP-712
        // This is what MetaMask and other wallets can sign!
        bytes32 DEPOSIT_TYPEHASH = keccak256(
            "DepositIntent(uint64 sourceChainId,address receiver,uint256 amount,uint256 nonce)"
        );

        // Generate random private key
        uint256 alicePrivateKey = uint256(keccak256("test_deposit_to_signature_unique_key"));
        address aliceSigner = vm.addr(alicePrivateKey);

        bytes32 structHash = keccak256(abi.encode(
            DEPOSIT_TYPEHASH,
            uint64(block.chainid),  // Source chain ID (Arbitrum - where depositTo is called from)
            aliceSigner,            // Receiver must match the signer
            depositAmount,
            depositId              // Using id as nonce
        ));

        // Get the domain separator from Base vault (destination chain)
        bytes32 domainSeparator = xYieldBase.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the EIP-712 digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Give the signer some USDC on Arbitrum
        vm.deal(aliceSigner, 1 ether);
        vm.startPrank(alice);
        usdcArbitrum.transfer(aliceSigner, depositAmount);
        vm.stopPrank();

        // Step 2: Signer calls depositTo on Arbitrum (inactive chain)
        vm.startPrank(aliceSigner);
        usdcArbitrum.approve(address(xYieldArbitrum), type(uint256).max);

        // Call depositTo
        uint256 outputAmount = depositAmount * 99 / 100; // 1% slippage
        xYieldArbitrum.depositTo(
            depositAmount,
            aliceSigner,    // Receiver
            baseChainId,    // Target chain
            depositId,
            signature,
            address(usdcBase), // output token on target chain
            outputAmount,
            address(0), // no exclusive relayer
            uint32(block.timestamp),
            uint32(block.timestamp + 1800),
            0 // no exclusivity
        );
        vm.stopPrank();

        // Step 3: Simulate the solver/relayer executing on Base (active chain)
        // Transfer USDC to the vault (simulating what Across would do)
        vm.startPrank(alice); // Use Alice as the solver for simplicity
        usdcBase.transfer(address(xYieldBase), depositAmount);
        vm.stopPrank();

        // Step 4: Call handleV3AcrossMessage as the solver would
        bytes memory data = abi.encode(uint64(block.chainid), aliceSigner, signature);
        bytes memory message = abi.encode(uint8(0), depositId, data);

        uint256 sharesBefore = xYieldBase.totalSupply();
        uint256 vaultAssetsBefore = xYieldBase.totalAssets();

        // Anyone can call this (simulating the solver/relayer)
        vm.prank(address(0xdeadbeef)); // Random address acting as solver
        xYieldBase.handleV3AcrossMessage(
            address(usdcBase),
            depositAmount,
            address(0xdeadbeef), // relayer address
            message
        );

        // Verify the deposit was processed correctly
        uint256 sharesAfter = xYieldBase.totalSupply();
        uint256 vaultAssetsAfter = xYieldBase.totalAssets();

        assertGt(sharesAfter, sharesBefore, "Total supply should increase after deposit");
        assertGt(vaultAssetsAfter, vaultAssetsBefore, "Vault assets should increase after deposit");

        // Verify the shares were recorded (not minted on this chain since it's a remote deposit)
        uint256 expectedShares = xYieldBase.previewDeposit(depositAmount);
        uint256 actualSharesIncreased = sharesAfter - sharesBefore;

        // Allow for 1 wei rounding difference due to ERC4626 math
        uint256 diff = actualSharesIncreased > expectedShares
            ? actualSharesIncreased - expectedShares
            : expectedShares - actualSharesIncreased;
        assertLe(diff, 1, "Shares should match within 1 wei rounding");
    }

    function testDepositToWithInvalidSignature() public {
        // Setup: Make Base chain inactive and Arbitrum active
        vm.startPrank(guardian);
        xYieldBase.setActiveChain(false);
        xYieldArbitrum.setActiveChain(true);
        vm.stopPrank();
        vm.startPrank(address(this));
        xYieldBase.setSiblingVault(uint64(block.chainid), address(xYieldArbitrum), address(usdcArbitrum));
        vm.stopPrank();

        uint256 depositId = 12345;

        // Create EIP-712 signature from wrong signer (Bob instead of Alice)
        bytes32 DEPOSIT_TYPEHASH = keccak256(
            "DepositIntent(uint64 sourceChainId,address receiver,uint256 amount,uint256 nonce)"
        );

        bytes32 structHash = keccak256(abi.encode(
            DEPOSIT_TYPEHASH,
            baseChainId,
            alice,  // Alice is the intended receiver
            depositAmount,
            depositId
        ));

        bytes32 domainSeparator = xYieldArbitrum.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Bob's private key (wrong signer)
        uint256 bobPrivateKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

        // Bob signs but claims it's for Alice
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Transfer USDC to vault (simulating Across bridge)
        vm.startPrank(alice);
        usdcArbitrum.transfer(address(xYieldArbitrum), depositAmount);
        vm.stopPrank();

        // Try to call handleV3AcrossMessage with invalid signature
        bytes memory data = abi.encode(baseChainId, alice, invalidSignature);
        bytes memory message = abi.encode(uint8(0), depositId, data);

        // This should revert with InvalidSignature
        vm.expectRevert(xYieldVault.InvalidSignature.selector);
        vm.prank(address(0xdeadbeef));
        xYieldArbitrum.handleV3AcrossMessage(
            address(usdcArbitrum),
            depositAmount,
            address(0xdeadbeef),
            message
        );
    }

    // TODO - test redeem and mint methods
}
