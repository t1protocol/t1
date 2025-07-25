// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L1MessageQueue } from "../L1/rollup/L1MessageQueue.sol";
import { L2GasPriceOracle } from "../L1/rollup/L2GasPriceOracle.sol";

import { T1TestBase } from "./T1TestBase.t.sol";

contract L1MessageQueueTest is T1TestBase {
    // events
    event QueueTransaction(
        address indexed sender, address indexed target, uint256 value, uint64 queueIndex, uint256 gasLimit, bytes data
    );
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);
    event ResetDequeuedTransaction(uint256 startIndex);
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);
    event DropTransaction(uint256 index);
    event UpdateGasOracle(address indexed _oldGasOracle, address indexed _newGasOracle);
    event UpdateMaxGasLimit(uint256 _oldMaxGasLimit, uint256 _newMaxGasLimit);

    address private FakeT1Chain = 0x1000000000000000000000000000000000000001;
    address private FakeMessenger = 0x1000000000000000000000000000000000000002;
    address private FakeGateway = 0x1000000000000000000000000000000000000003;
    address private FakeSigner = 0x1000000000000000000000000000000000000004;

    L1MessageQueue private queue;
    L2GasPriceOracle private gasOracle;

    function setUp() public {
        __T1TestBase_setUp();

        queue = L1MessageQueue(_deployProxy(address(0)));
        gasOracle = L2GasPriceOracle(_deployProxy(address(new L2GasPriceOracle())));

        // Upgrade the L1MessageQueue implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(queue)), address(new L1MessageQueue()));
        gasOracle.initialize(21_000, 50_000, 8, 16);
        queue.initialize(address(gasOracle), 10_000_000);
    }

    function testInitialize() external {
        assertEq(queue.owner(), address(this));
        assertEq(queue.gasOracle(), address(gasOracle));
        assertEq(queue.maxGasLimit(), 10_000_000);

        vm.expectRevert("Initializable: contract is already initialized");
        queue.initialize(address(0), 0);
    }

    function testUpdateGasOracle(address newGasOracle) external {
        // call by non-owner, should revert
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        queue.updateGasOracle(newGasOracle);
        vm.stopPrank();

        // call by owner, should succeed
        assertEq(queue.gasOracle(), address(gasOracle));
        vm.expectEmit(true, true, false, true);
        emit UpdateGasOracle(address(gasOracle), newGasOracle);
        queue.updateGasOracle(newGasOracle);
        assertEq(queue.gasOracle(), newGasOracle);
    }

    function testUpdateMaxGasLimit(uint256 newMaxGasLimit) external {
        // call by non-owner, should revert
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        queue.updateMaxGasLimit(newMaxGasLimit);
        vm.stopPrank();

        // call by owner, should succeed
        assertEq(queue.maxGasLimit(), 10_000_000);
        vm.expectEmit(true, true, false, true);
        emit UpdateMaxGasLimit(10_000_000, newMaxGasLimit);
        queue.updateMaxGasLimit(newMaxGasLimit);
        assertEq(queue.maxGasLimit(), newMaxGasLimit);
    }

    function testAppendCrossDomainMessage(uint256 gasLimit, bytes memory data) external {
        gasLimit = bound(gasLimit, 21_000 + data.length * 16, 10_000_000);

        vm.startPrank(FakeMessenger);

        // should revert, when exceed maxGasLimit
        vm.expectRevert("Gas limit must not exceed maxGasLimit");
        queue.appendCrossDomainMessage(address(0), 10_000_001, "0x");

        // should revert, when below intrinsic gas
        vm.expectRevert("Insufficient gas limit, must be above intrinsic gas");
        queue.appendCrossDomainMessage(address(0), 0, "0x");

        // should succeed
        assertEq(queue.nextCrossDomainMessageIndex(), 0);
        address sender = address(uint160(FakeMessenger) + uint160(0x1111000000000000000000000000000000001111));
        bytes32 hash0 = queue.computeTransactionHash(sender, 0, 0, FakeSigner, gasLimit, data);
        vm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 0, gasLimit, data);
        queue.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 1);
        assertEq(queue.getCrossDomainMessage(0), hash0);

        bytes32 hash1 = queue.computeTransactionHash(sender, 1, 0, FakeSigner, gasLimit, data);
        vm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 1, gasLimit, data);
        queue.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 2);
        assertEq(queue.getCrossDomainMessage(0), hash0);
        assertEq(queue.getCrossDomainMessage(1), hash1);

        vm.stopPrank();
    }

    function testPopCrossDomainMessage(uint256 bitmap) external {
        // should revert, when pop too many messages
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("pop too many messages");
        queue.popCrossDomainMessage(0, 257, 0);
        vm.stopPrank();

        // should revert, when start index mismatch
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("start index mismatch");
        queue.popCrossDomainMessage(1, 256, 0);
        vm.stopPrank();

        // should succeed
        // append 512 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; ++i) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // pop 50 messages with no skip
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 50, 0);
        queue.popCrossDomainMessage(0, 50, 0);
        assertEq(queue.pendingQueueIndex(), 50);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 0; i < 50; i++) {
            assertEq(queue.isMessageSkipped(i), false);
            assertEq(queue.isMessageDropped(i), false);
        }

        // pop 10 messages all skip
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(50, 10, 1023);
        queue.popCrossDomainMessage(50, 10, 1023);
        assertEq(queue.pendingQueueIndex(), 60);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 50; i < 60; i++) {
            assertEq(queue.isMessageSkipped(i), true);
            assertEq(queue.isMessageDropped(i), false);
        }
        assertEq(queue.isMessageSkipped(60), false);

        // pop 20 messages, skip first 5
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(60, 20, 31);
        queue.popCrossDomainMessage(60, 20, 31);
        assertEq(queue.pendingQueueIndex(), 80);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 60; i < 65; i++) {
            assertEq(queue.isMessageSkipped(i), true);
            assertEq(queue.isMessageDropped(i), false);
        }
        for (uint256 i = 65; i < 80; i++) {
            assertEq(queue.isMessageSkipped(i), false);
            assertEq(queue.isMessageDropped(i), false);
        }

        // pop 256 messages with random skip
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(80, 256, bitmap);
        queue.popCrossDomainMessage(80, 256, bitmap);
        assertEq(queue.pendingQueueIndex(), 336);
        for (uint256 i = 80; i < 80 + 256; i++) {
            assertEq(queue.isMessageSkipped(i), ((bitmap >> (i - 80)) & 1) == 1);
            assertEq(queue.isMessageDropped(i), false);
        }

        vm.stopPrank();
    }

    function testPopCrossDomainMessageRandom(
        uint256 count1,
        uint256 count2,
        uint256 count3,
        uint256 bitmap1,
        uint256 bitmap2,
        uint256 bitmap3
    )
        external
    {
        count1 = bound(count1, 1, 256);
        count2 = bound(count2, 1, 256);
        count3 = bound(count3, 1, 256);
        // append count1 + count2 + count3 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < count1 + count2 + count3; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        vm.startPrank(FakeT1Chain);
        // first pop `count1` messages
        vm.expectEmit(false, false, false, true);
        if (count1 == 256) {
            emit DequeueTransaction(0, count1, bitmap1);
        } else {
            emit DequeueTransaction(0, count1, bitmap1 & ((1 << count1) - 1));
        }
        queue.popCrossDomainMessage(0, count1, bitmap1);
        assertEq(queue.pendingQueueIndex(), count1);
        for (uint256 i = 0; i < count1; i++) {
            assertEq(queue.isMessageSkipped(i), ((bitmap1 >> i) & 1) == 1);
            assertEq(queue.isMessageDropped(i), false);
        }

        // then pop `count2` messages
        vm.expectEmit(false, false, false, true);
        if (count2 == 256) {
            emit DequeueTransaction(count1, count2, bitmap2);
        } else {
            emit DequeueTransaction(count1, count2, bitmap2 & ((1 << count2) - 1));
        }
        queue.popCrossDomainMessage(count1, count2, bitmap2);
        assertEq(queue.pendingQueueIndex(), count1 + count2);
        for (uint256 i = 0; i < count2; i++) {
            assertEq(queue.isMessageSkipped(i + count1), ((bitmap2 >> i) & 1) == 1);
            assertEq(queue.isMessageDropped(i + count1), false);
        }

        // last pop `count3` messages
        vm.expectEmit(false, false, false, true);
        if (count3 == 256) {
            emit DequeueTransaction(count1 + count2, count3, bitmap3);
        } else {
            emit DequeueTransaction(count1 + count2, count3, bitmap3 & ((1 << count3) - 1));
        }
        queue.popCrossDomainMessage(count1 + count2, count3, bitmap3);
        assertEq(queue.pendingQueueIndex(), count1 + count2 + count3);
        for (uint256 i = 0; i < count3; i++) {
            assertEq(queue.isMessageSkipped(i + count1 + count2), ((bitmap3 >> i) & 1) == 1);
            assertEq(queue.isMessageDropped(i + count1 + count2), false);
        }
        vm.stopPrank();
    }

    function testResetPoppedCrossDomainMessage(uint256 startIndex) external {
        // should do nothing
        vm.startPrank(FakeT1Chain);
        queue.resetPoppedCrossDomainMessage(0);
        vm.stopPrank();

        // append 512 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // pop 256 messages with no skip
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 256, 0);
        queue.popCrossDomainMessage(0, 256, 0);
        assertEq(queue.pendingQueueIndex(), 256);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        vm.stopPrank();

        // finalize 128 messages
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(127);
        queue.finalizePoppedCrossDomainMessage(128);
        assertEq(queue.nextUnfinalizedQueueIndex(), 128);
        vm.stopPrank();

        // should revert, when reset finalized messages
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("reset finalized messages");
        queue.resetPoppedCrossDomainMessage(127);
        vm.stopPrank();

        // should revert, when reset pending messages
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("reset pending messages");
        queue.resetPoppedCrossDomainMessage(257);
        vm.stopPrank();

        // should succeed
        startIndex = bound(startIndex, 128, 256);
        vm.startPrank(FakeT1Chain);
        if (startIndex < 256) {
            vm.expectEmit(false, false, false, true);
            emit ResetDequeuedTransaction(startIndex);
        }
        queue.resetPoppedCrossDomainMessage(startIndex);
        assertEq(queue.pendingQueueIndex(), startIndex);
        assertEq(queue.nextUnfinalizedQueueIndex(), 128);
        vm.stopPrank();
    }

    // pop, reset, pop, reset, pop
    // solhint-disable-next-line code-complexity
    function testResetPoppedCrossDomainMessageRandom(
        uint256 bitmap1,
        uint256 bitmap2,
        uint256 startIndex1,
        uint256 startIndex2
    )
        external
    {
        // append 1024 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // first pop 512 messages
        vm.startPrank(FakeT1Chain);
        queue.popCrossDomainMessage(0, 256, bitmap1);
        assertEq(queue.pendingQueueIndex(), 256);
        queue.popCrossDomainMessage(256, 256, bitmap2);
        assertEq(queue.pendingQueueIndex(), 512);
        vm.stopPrank();

        for (uint256 i = 0; i < 512; ++i) {
            if (i < 256) {
                assertEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
            } else {
                assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
            }
        }

        // first reset
        startIndex1 = bound(startIndex1, 0, 512);
        vm.startPrank(FakeT1Chain);
        queue.resetPoppedCrossDomainMessage(startIndex1);
        vm.stopPrank();
        assertEq(queue.pendingQueueIndex(), startIndex1);
        for (uint256 i = 0; i < 512; ++i) {
            if (i >= startIndex1) {
                assertEq(queue.isMessageSkipped(i), false);
                continue;
            }
            if (i < 256) {
                assertEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
            } else {
                assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
            }
        }

        // next pop 512 messages
        vm.startPrank(FakeT1Chain);
        queue.popCrossDomainMessage(startIndex1, 256, bitmap1);
        assertEq(queue.pendingQueueIndex(), startIndex1 + 256);
        queue.popCrossDomainMessage(startIndex1 + 256, 256, bitmap2);
        assertEq(queue.pendingQueueIndex(), startIndex1 + 512);
        vm.stopPrank();

        for (uint256 i = 0; i < startIndex1 + 512; ++i) {
            if (i < startIndex1) {
                if (i < 256) {
                    assertEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
                } else {
                    assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
                }
            } else {
                uint256 offset = i - startIndex1;
                if (offset < 256) {
                    assertEq(queue.isMessageSkipped(i), ((bitmap1) >> offset) & 1 == 1);
                } else {
                    assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (offset - 256)) & 1 == 1);
                }
            }
        }

        // second reset
        startIndex2 = bound(startIndex2, 0, startIndex1 + 512);
        vm.startPrank(FakeT1Chain);
        queue.resetPoppedCrossDomainMessage(startIndex2);
        vm.stopPrank();
        assertEq(queue.pendingQueueIndex(), startIndex2);
        for (uint256 i = 0; i < startIndex1 + 512; ++i) {
            if (i >= startIndex2) {
                assertEq(queue.isMessageSkipped(i), false);
                continue;
            }
            if (i < startIndex1) {
                if (i < 256) {
                    assertEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
                } else {
                    assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
                }
            } else {
                uint256 offset = i - startIndex1;
                if (offset < 256) {
                    assertEq(queue.isMessageSkipped(i), ((bitmap1) >> offset) & 1 == 1);
                } else {
                    assertEq(queue.isMessageSkipped(i), ((bitmap2) >> (offset - 256)) & 1 == 1);
                }
            }
        }
    }

    function testFinalizePoppedCrossDomainMessage() external {
        // append 10 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // pop 5 messages with no skip
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 5, 0);
        queue.popCrossDomainMessage(0, 5, 0);
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        vm.stopPrank();

        // should revert, when finalized index too large
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("finalized index too large");
        queue.finalizePoppedCrossDomainMessage(6);
        vm.stopPrank();

        // should succeed
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(4);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        vm.stopPrank();

        // should revert, finalized index too small
        vm.startPrank(FakeT1Chain);
        vm.expectRevert("finalized index too small");
        queue.finalizePoppedCrossDomainMessage(4);
        vm.stopPrank();

        // should do nothing
        vm.startPrank(FakeT1Chain);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        vm.stopPrank();
    }

    function testDropCrossDomainMessageFailed() external {
        // should revert, when drop non-skipped message
        // append 10 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // pop 5 messages with no skip
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 5, 0);
        queue.popCrossDomainMessage(0, 5, 0);
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        vm.stopPrank();

        // drop pending message
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
        }
        vm.stopPrank();

        vm.startPrank(FakeT1Chain);
        queue.finalizePoppedCrossDomainMessage(5);
        vm.stopPrank();
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);

        // drop non-skipped message
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert("drop non-skipped message");
            queue.dropCrossDomainMessage(i);
        }
        vm.stopPrank();

        // drop pending message
        vm.startPrank(FakeMessenger);
        for (uint256 i = 5; i < 10; i++) {
            vm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
        }
        vm.stopPrank();
    }

    function testDropCrossDomainMessageSucceed() external {
        // append 10 messages
        vm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1_000_000, "0x");
        }
        vm.stopPrank();

        // pop 10 messages, all skipped
        vm.startPrank(FakeT1Chain);
        vm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 10, 0x3ff);
        queue.popCrossDomainMessage(0, 10, 0x3ff);
        assertEq(queue.pendingQueueIndex(), 10);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.pendingQueueIndex(), 10);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            assertEq(queue.isMessageSkipped(i), true);
            assertEq(queue.isMessageDropped(i), false);
            vm.startPrank(FakeMessenger);
            vm.expectEmit(false, false, false, true);
            emit DropTransaction(i);
            queue.dropCrossDomainMessage(i);

            vm.expectRevert("message already dropped");
            queue.dropCrossDomainMessage(i);
            vm.stopPrank();

            assertEq(queue.isMessageSkipped(i), true);
            assertEq(queue.isMessageDropped(i), true);
        }
        for (uint256 i = 5; i < 10; i++) {
            assertEq(queue.isMessageSkipped(i), true);
            assertEq(queue.isMessageDropped(i), false);

            vm.startPrank(FakeMessenger);
            vm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
            vm.stopPrank();
        }
    }
}
