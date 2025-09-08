// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { xYieldVault } from "../../xYield/xYieldVault.sol";
import { MockYieldProtocol } from "./MockYieldProtocol.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import {
    IOriginSettler,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction,
    OnchainCrossChainOrder
} from "../../interfaces/IERC7683.sol";
import { IT1ERC7683 } from "../../interfaces/IT1ERC7683.sol";
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

contract xYieldTest is Test {
    xYieldVault public vault;
    Mock4626 public yieldProtocol; // mocking a vault
    MockUSDC public usdc;
    T1XChainReader public reader;
    T1ERC7683 public settler;

    address public guardian = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public prover = address(0x4);
    address public acrossSpokePool = address(0x5);

    uint256 public constant INITIAL_DEPOSIT = 1000 * 10 ** 18;

    address[] emptyAddresses;
    uint256[] emptyAmounts;

    function setUp() public {
        usdc = new MockUSDC();
        yieldProtocol = new Mock4626(IERC20(address(usdc)), "Euler USDC", "eUSDC", true);
        reader = new T1XChainReader(prover);
        settler = new T1ERC7683(address(0), address(reader), uint32(block.chainid));

        // Initialize the T1ERC7683 contract
        settler.initialize(address(0x1234), address(0x5678));

        vault = new xYieldVault(
            IERC20(address(usdc)),
            guardian,
            "xYield USDC",
            "xyUSDC",
            address(yieldProtocol),
            address(settler),
            acrossSpokePool
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
        vault.setSiblingVault(1, address(0x4));

        vm.prank(user1);
        vault.depositFrom(depositAmount, user1, 1);
    }

    function testRebalance() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        vm.expectEmit(true, true, true, true);
        emit xYieldVault.Rebalanced(dstChainId, depositAmount);

        // Record logs to check if Open event was emitted
        vm.recordLogs();

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.prank(guardian);
        vault.rebalance(dstChainId, depositAmount, order);

        // Check that Open event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool openEventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(settler) && logs[i].topics[0] == IOriginSettler.Open.selector) {
                openEventFound = true;
                break;
            }
        }
        assertTrue(openEventFound, "Open event should have been emitted");

        assertFalse(vault.isActiveChain());
        assertEq(vault.virtualTotalAssets(), 0);
        assertEq(usdc.balanceOf(address(settler)), depositAmount, "settler should have the rebalanced amount");
    }

    function testRebalanceZeroAmountRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, 0, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.ZeroAmount.selector);
        vm.prank(guardian);
        vault.rebalance(dstChainId, 0, order);
    }

    function testRebalanceWithdrawOnInactiveChainRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        vm.prank(guardian);
        vault.setActiveChain(false);

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.WithdrawOnInactiveChain.selector);
        vm.prank(guardian);
        vault.rebalance(dstChainId, depositAmount, order);
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
        vault.rebalance(dstChainId, depositAmount, order);
    }

    function testRebalanceInvalidOrderDataDestinationDomainRevert() public {
        uint32 dstChainId = 1;
        uint32 wrongChainId = 2;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Create order with wrong destination domain
        OnchainCrossChainOrder memory order =
            _createOrder(wrongChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.InvalidOrderData.selector);
        vm.prank(guardian);
        vault.rebalance(dstChainId, depositAmount, order);
    }

    function testRebalanceInvalidOrderDataAmountInRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 wrongAmount = 50 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Create order with wrong amount
        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, wrongAmount, wrongAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.InvalidOrderData.selector);
        vm.prank(guardian);
        vault.rebalance(dstChainId, depositAmount, order);
    }

    function testRebalanceNotGuardianRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, depositAmount, depositAmount, uint32(block.timestamp + 10_000_000), 0, false);

        vm.expectRevert(xYieldVault.NotGuardian.selector);
        vault.rebalance(dstChainId, depositAmount, order);
    }

    function testUndoRebalance() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 usdcBalance = usdc.balanceOf(address(yieldProtocol));
        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, usdcBalance, usdcBalance, uint32(block.timestamp), 0, false);

        // Record logs to capture the orderId from Open event
        vm.recordLogs();
        vm.prank(guardian);
        vault.rebalance(dstChainId, usdcBalance, order);

        // Extract orderId from Open event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 orderId;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(settler) && logs[i].topics[0] == IOriginSettler.Open.selector) {
                orderId = logs[i].topics[1]; // orderId is the first indexed parameter
                break;
            }
        }

        // Warp time to make intent deadline pass
        vm.warp(block.timestamp + 1_000_000);

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(address(reader), abi.encodeWithSelector(reader.requestRead.selector), abi.encode(expectedRequestId));
        settler.verifyRefund(orderId);

        // Mock the cross-chain read to return empty result (order not filled)
        vm.mockCall(
            address(reader),
            abi.encodeWithSelector(reader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        bytes memory proof = "mock_proof";

        vm.prank(guardian);
        vault.undoRebalance(order, proof);

        assertTrue(vault.isActiveChain());
        assertEq(vault.virtualTotalAssets(), usdcBalance);
        assertEq(uint8(settler.orderStatus(orderId)), uint8(5), "Order status should be REFUNDED");
        assertEq(usdc.balanceOf(address(yieldProtocol)), usdcBalance, "yieldProtocol should get the amount returned");
    }

    function testUndoRebalanceNotGuardianRevert() public {
        uint32 dstChainId = 1;
        uint256 depositAmount = 100 * 10 ** 18;

        vault.setSiblingVault(dstChainId, address(12));

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 usdcBalance = usdc.balanceOf(address(yieldProtocol));
        OnchainCrossChainOrder memory order =
            _createOrder(dstChainId, usdcBalance, usdcBalance, uint32(block.timestamp), 0, false);

        // Record logs to capture the orderId from Open event
        vm.recordLogs();
        vm.prank(guardian);
        vault.rebalance(dstChainId, usdcBalance, order);

        // Extract orderId from Open event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 orderId;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(settler) && logs[i].topics[0] == IOriginSettler.Open.selector) {
                orderId = logs[i].topics[1]; // orderId is the first indexed parameter
                break;
            }
        }

        // Warp time to make intent deadline pass
        vm.warp(block.timestamp + 1_000_000);

        bytes32 expectedRequestId = keccak256("mock_request_id");
        vm.mockCall(address(reader), abi.encodeWithSelector(reader.requestRead.selector), abi.encode(expectedRequestId));
        settler.verifyRefund(orderId);

        // Mock the cross-chain read to return empty result (order not filled)
        vm.mockCall(
            address(reader),
            abi.encodeWithSelector(reader.verifyProofOfRead.selector),
            abi.encode(expectedRequestId, bytes(""))
        );

        bytes memory proof = "mock_proof";

        vm.expectRevert(xYieldVault.NotGuardian.selector);
        vault.undoRebalance(order, proof);
    }

    function testReDepositIdleAssets() public {
        uint256 idleAmount = 50 * 10 ** 18;
        usdc.mint(address(vault), idleAmount);

        vault.reDepositIdleAssets();

        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(yieldProtocol.balanceOf(address(vault)), idleAmount);
    }

    function testReDepositIdleAssetsZeroAmountRevert() public {
        // No USDC is available on vault
        vm.expectRevert(xYieldVault.ZeroAmount.selector);
        vault.reDepositIdleAssets();
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
        address siblingVault = vault.siblingVaults(dstChainId);

        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(address(vault)),
            recipient: TypeCasts.addressToBytes32(siblingVault),
            inputToken: TypeCasts.addressToBytes32(address(usdc)),
            outputToken: TypeCasts.addressToBytes32(address(usdc)),
            amountIn: amount,
            minAmountOut: minAmountOut,
            senderNonce: nonce,
            originDomain: uint32(block.chainid),
            destinationDomain: dstChainId,
            destinationSettler: TypeCasts.addressToBytes32(T1ERC7683(address(settler)).counterpart()),
            fillDeadline: fillDeadline,
            closedAuction: closedAuction,
            data: new bytes(0)
        });

        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: OrderEncoder.orderDataType(),
            orderData: abi.encode(orderData)
        });
    }
}
