// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { V3SpokePoolInterface } from "@across-protocol/contracts/contracts/interfaces/V3SpokePoolInterface.sol";

import { xYieldVault } from "../../xYield/xYieldVault.sol";
import { MockYieldProtocol } from "./MockYieldProtocol.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import {
    IOriginSettler,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction,
    OnchainCrossChainOrder
} from "../../interfaces/IERC7683.sol";
import { OrderData, OrderEncoder } from "../../libraries/7683/OrderEncoder.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

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

contract MockSpokePool {
    function depositV3(
        address,
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint32,
        uint32,
        uint32,
        bytes calldata
    )
        external
        payable
    { }

    function counterpart() external pure returns (address) {
        return address(0x1234);
    }
}

contract xYieldTest is Test {
    xYieldVault public vault;
    Mock4626 public yieldProtocol; // mocking a vault
    MockUSDC public usdc;
    T1XChainReader public reader;
    MockSpokePool public bridge;

    address public guardian = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public prover = address(0x4);

    uint256 public constant INITIAL_DEPOSIT = 1000 * 10 ** 18;
    uint256 public constant REBALANCE_ID = 1;

    address[] emptyAddresses;
    uint256[] emptyAmounts;

    function setUp() public {
        usdc = new MockUSDC();
        yieldProtocol = new Mock4626(IERC20(address(usdc)), "Euler USDC", "eUSDC", true);
        reader = new T1XChainReader(prover);
        bridge = new MockSpokePool();

        vault = new xYieldVault(
            IERC20(address(usdc)), guardian, "xYield USDC", "xyUSDC", address(yieldProtocol), address(bridge)
        );

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

        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](2);
        balanceUpdates[0] =
            xYieldVault.BalanceUpdate({ recipient: user1, amount: 100 * 10 ** 18, txType: xYieldVault.TxType.Deposit });
        balanceUpdates[1] =
            xYieldVault.BalanceUpdate({ recipient: user2, amount: 100 * 10 ** 18, txType: xYieldVault.TxType.Deposit });

        vm.prank(guardian);
        vault.updateTotals(newVirtualTotalSupply, balanceUpdates);

        assertEq(vault.virtualTotalSupply(), newVirtualTotalSupply, "virtual total supply");

        vm.prank(guardian);
        vault.setActiveChain(false);

        assertFalse(vault.isActiveChain(), "is active chain");
    }

    function testRevertOnUnauthorizedAccess() public {
        vm.expectRevert(abi.encodeWithSelector(xYieldVault.NotGuardian.selector));
        vm.prank(user1);
        xYieldVault.BalanceUpdate[] memory balanceUpdates = new xYieldVault.BalanceUpdate[](0);
        vault.updateTotals(100, balanceUpdates);

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
        vault.setSiblingVault(1, address(0x4), address(usdc));

        vm.prank(user1);
        vault.depositFrom(depositAmount, user1, 1);
    }

    function testRebalance() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12), address(usdc));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        vm.expectEmit(true, true, true, true);
        emit xYieldVault.RebalanceInitiated(REBALANCE_ID, dstChainId, depositAmount);

        // Record logs to check if Open event was emitted
        vm.recordLogs();

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.prank(guardian);
        vault.rebalance(REBALANCE_ID, dstChainId, depositAmount, depositAmount, 0);

        assertFalse(vault.isActiveChain());
        assertEq(vault.virtualTotalAssets(), 0);
    }

    function testRebalanceZeroAmountRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12), address(usdc));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, 0, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.ZeroAmount.selector);
        vm.prank(guardian);
        vault.rebalance(REBALANCE_ID, dstChainId, 0, 0, 0);
    }

    function testRebalanceWithdrawOnInactiveChainRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12), address(usdc));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        vm.prank(guardian);
        vault.setActiveChain(false);

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.WithdrawOnInactiveChain.selector);
        vm.prank(guardian);
        vault.rebalance(REBALANCE_ID, dstChainId, depositAmount, depositAmount, 0);
    }

    function testRebalanceInvalidChainRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.InvalidChain.selector);
        vm.prank(guardian);
        vault.rebalance(REBALANCE_ID, dstChainId, depositAmount, depositAmount, 0);
    }

    function testRebalanceNotGuardianRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.NotGuardian.selector);
        vault.rebalance(REBALANCE_ID, dstChainId, depositAmount, depositAmount, 0);
    }

    function _createOrder(
        uint32 dstChainId,
        uint256 amount,
        uint256 minAmountOut,
        uint32 fillDeadline,
        uint256 nonce,
        bool closedAuction
    )
        internal
        view
        returns (OnchainCrossChainOrder memory)
    {
        OrderData memory orderData;
        {
            (address siblingVault,) = vault.siblingVaults(dstChainId);
            orderData = OrderData({
                sender: TypeCasts.addressToBytes32(address(vault)),
                recipient: TypeCasts.addressToBytes32(siblingVault),
                inputToken: TypeCasts.addressToBytes32(address(usdc)),
                outputToken: TypeCasts.addressToBytes32(address(usdc)),
                amountIn: amount,
                minAmountOut: minAmountOut,
                senderNonce: nonce,
                originDomain: uint32(block.chainid),
                destinationDomain: dstChainId,
                destinationSettler: TypeCasts.addressToBytes32(MockSpokePool(address(bridge)).counterpart()),
                fillDeadline: fillDeadline,
                closedAuction: closedAuction,
                data: new bytes(0)
            });
        }

        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: OrderEncoder.orderDataType(),
            orderData: abi.encode(orderData)
        });
    }
}
