// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IL1T1Messenger } from "../L1/L1T1Messenger.sol";

import { L1GatewayTestBase } from "./L1GatewayTestBase.t.sol";

contract L1T1MessengerTest is L1GatewayTestBase {
    event OnDropMessageCalled(bytes);
    event UpdateMaxReplayTimes(uint256 oldMaxReplayTimes, uint256 newMaxReplayTimes);

    function setUp() public {
        __L1GatewayTestBase_setUp();
    }

    function testForbidCallMessageQueueFromL2() external {
        bytes32 _xDomainCalldataHash = keccak256(
            abi.encodeWithSignature(
                "relayMessage(address,address,uint256,uint256,bytes)",
                address(this),
                address(messageQueue),
                0,
                0,
                new bytes(0)
            )
        );
        prepareL2MessageRoot(_xDomainCalldataHash);

        // IL1T1Messenger.L2MessageProof memory proof;
        // proof.batchIndex = rollup.lastFinalizedBatchIndex();

        hevm.expectRevert("Forbid to call message queue");
        // l1Messenger.relayMessageWithProof(address(this), address(messageQueue), 0, 0, new bytes(0), proof);
        l1Messenger.relayMessageWithProof(address(this), address(messageQueue), 0, 0, new bytes(0));
    }

    function testForbidCallSelfFromL2() external {
        bytes32 _xDomainCalldataHash = keccak256(
            abi.encodeWithSignature(
                "relayMessage(address,address,uint256,uint256,bytes)",
                address(this),
                address(l1Messenger),
                0,
                0,
                new bytes(0)
            )
        );
        prepareL2MessageRoot(_xDomainCalldataHash);
        // IL1T1Messenger.L2MessageProof memory proof;
        // proof.batchIndex = rollup.lastFinalizedBatchIndex();

        hevm.expectRevert("Forbid to call self");
        // l1Messenger.relayMessageWithProof(address(this), address(l1Messenger), 0, 0, new bytes(0), proof);
        l1Messenger.relayMessageWithProof(address(this), address(l1Messenger), 0, 0, new bytes(0));
    }

    function testSendMessage(uint256 exceedValue, address refundAddress) external {
        hevm.assume(refundAddress.code.length == 0);
        hevm.assume(uint256(uint160(refundAddress)) > 100); // ignore some precompile contracts
        hevm.assume(refundAddress != address(0x000000000000000000636F6e736F6c652e6c6f67)); // ignore console/console2

        exceedValue = bound(exceedValue, 1, address(this).balance / 2);

        // Insufficient msg.value
        hevm.expectRevert("Insufficient msg.value");
        l1Messenger.sendMessage(address(0), 1, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);

        // refund exceed fee
        uint256 balanceBefore = refundAddress.balance;
        l1Messenger.sendMessage{ value: 1 + exceedValue }(address(0), 1, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);
        assertEq(balanceBefore + exceedValue, refundAddress.balance);
    }

    function testReplayMessage(uint256 exceedValue, address refundAddress) external {
        hevm.assume(refundAddress.code.length == 0);
        hevm.assume(uint256(uint160(refundAddress)) > uint256(100)); // ignore some precompile contracts
        hevm.assume(refundAddress != feeVault);
        hevm.assume(refundAddress != address(0x000000000000000000636F6e736F6c652e6c6f67)); // ignore console/console2

        exceedValue = bound(exceedValue, 1, address(this).balance / 2);

        l1Messenger.updateMaxReplayTimes(0);

        // append a message
        l1Messenger.sendMessage{ value: 100 }(address(0), 100, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);

        // Provided message has not been enqueued
        hevm.expectRevert("Provided message has not been enqueued");
        l1Messenger.replayMessage(address(this), address(0), 101, 0, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);

        messageQueue.setL2BaseFee(1);
        // Insufficient msg.value
        hevm.expectRevert("Insufficient msg.value for fee");
        l1Messenger.replayMessage(address(this), address(0), 100, 0, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);

        uint256 _fee = messageQueue.l2BaseFee() * DEFAULT_GAS_LIMIT;

        // Exceed maximum replay times
        hevm.expectRevert("Exceed maximum replay times");
        l1Messenger.replayMessage{ value: _fee }(
            address(this), address(0), 100, 0, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress
        );

        l1Messenger.updateMaxReplayTimes(1);

        // refund exceed fee
        uint256 balanceBefore = refundAddress.balance;
        uint256 feeVaultBefore = feeVault.balance;
        l1Messenger.replayMessage{ value: _fee + exceedValue }(
            address(this), address(0), 100, 0, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress
        );
        assertEq(balanceBefore + exceedValue, refundAddress.balance);
        assertEq(feeVaultBefore + _fee, feeVault.balance);

        // test replay list
        // 1. send a message with nonce 2
        // 2. replay 3 times
        messageQueue.setL2BaseFee(0);
        l1Messenger.updateMaxReplayTimes(100);
        l1Messenger.sendMessage{ value: 100 }(address(0), 100, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);
        bytes32 hash = keccak256(
            abi.encodeWithSignature(
                "relayMessage(address,address,uint256,uint256,bytes)", address(this), address(0), 100, 2, new bytes(0)
            )
        );
        (uint256 _replayTimes, uint256 _lastIndex) = l1Messenger.replayStates(hash);
        assertEq(_replayTimes, 0);
        assertEq(_lastIndex, 0);
        for (uint256 i = 0; i < 3; i++) {
            l1Messenger.replayMessage(address(this), address(0), 100, 2, new bytes(0), DEFAULT_GAS_LIMIT, refundAddress);
            (_replayTimes, _lastIndex) = l1Messenger.replayStates(hash);
            assertEq(_replayTimes, i + 1);
            assertEq(_lastIndex, i + 3);
            assertEq(l1Messenger.prevReplayIndex(i + 3), i + 2 + 1);
            for (uint256 j = 0; j <= i; j++) {
                assertEq(l1Messenger.prevReplayIndex(i + 3 - j), i + 2 - j + 1);
            }
        }
    }

    function testUpdateMaxReplayTimes(uint256 _maxReplayTimes) external {
        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        l1Messenger.updateMaxReplayTimes(_maxReplayTimes);
        hevm.stopPrank();

        hevm.expectEmit(false, false, false, true);
        emit UpdateMaxReplayTimes(3, _maxReplayTimes);

        assertEq(l1Messenger.maxReplayTimes(), 3);
        l1Messenger.updateMaxReplayTimes(_maxReplayTimes);
        assertEq(l1Messenger.maxReplayTimes(), _maxReplayTimes);
    }

    function testSetPause() external {
        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        l1Messenger.setPause(false);
        hevm.stopPrank();

        // pause
        l1Messenger.setPause(true);
        assertBoolEq(true, l1Messenger.paused());

        hevm.expectRevert("Pausable: paused");
        l1Messenger.sendMessage(address(0), 0, new bytes(0), DEFAULT_GAS_LIMIT);
        hevm.expectRevert("Pausable: paused");
        l1Messenger.sendMessage(address(0), 0, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
        hevm.expectRevert("Pausable: paused");
        // IL1T1Messenger.L2MessageProof memory _proof;
        // l1Messenger.relayMessageWithProof(address(0), address(0), 0, 0, new bytes(0), _proof);
        l1Messenger.relayMessageWithProof(address(0), address(0), 0, 0, new bytes(0));
        hevm.expectRevert("Pausable: paused");
        l1Messenger.replayMessage(address(0), address(0), 0, 0, new bytes(0), 0, address(0));
        hevm.expectRevert("Pausable: paused");
        l1Messenger.dropMessage(address(0), address(0), 0, 0, new bytes(0));

        // unpause
        l1Messenger.setPause(false);
        assertBoolEq(false, l1Messenger.paused());
    }

    function testIntrinsicGasLimit() external {
        uint256 _fee = messageQueue.l2BaseFee() * 24_000;
        uint256 value = 1;

        // _xDomainCalldata contains
        //   4B function identifier
        //   20B sender addr (encoded as 32B)
        //   20B target addr (encoded as 32B)
        //   32B value
        //   32B nonce
        //   message byte array (32B offset + 32B length + bytes (padding to multiple of 32))
        // So the intrinsic gas must be greater than 21000 + 16 * 228 = 24648
        l1Messenger.sendMessage{ value: _fee + value }(address(0), value, hex"0011220033", 24_648);

        // insufficient intrinsic gas
        hevm.expectRevert("Insufficient gas limit, must be above intrinsic gas");
        l1Messenger.sendMessage{ value: _fee + value }(address(0), 1, hex"0011220033", 24_647);

        // gas limit exceeds the max value
        uint256 gasLimit = 100_000_000;
        _fee = messageQueue.l2BaseFee() * gasLimit;
        hevm.expectRevert("Gas limit must not exceed maxGasLimit");
        l1Messenger.sendMessage{ value: _fee + value }(address(0), value, hex"0011220033", gasLimit);

        // update max gas limit
        messageQueue.updateMaxGasLimit(gasLimit);
        l1Messenger.sendMessage{ value: _fee + value }(address(0), value, hex"0011220033", gasLimit);
    }

    function testDropMessage() external {
        // Provided message has not been enqueued, revert
        hevm.expectRevert("Provided message has not been enqueued");
        l1Messenger.dropMessage(address(0), address(0), 0, 0, new bytes(0));

        // send one message with nonce 0
        l1Messenger.sendMessage(address(0), 0, new bytes(0), DEFAULT_GAS_LIMIT);
        assertEq(messageQueue.nextCrossDomainMessageIndex(), 1);

        // drop pending message, revert
        hevm.expectRevert("cannot drop pending message");
        l1Messenger.dropMessage(address(this), address(0), 0, 0, new bytes(0));

        l1Messenger.updateMaxReplayTimes(10);

        // replay 1 time
        l1Messenger.replayMessage(address(this), address(0), 0, 0, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
        assertEq(messageQueue.nextCrossDomainMessageIndex(), 2);

        // skip all 2 messages
        hevm.startPrank(address(rollup));
        messageQueue.popCrossDomainMessage(0, 2, 0x3);
        messageQueue.finalizePoppedCrossDomainMessage(2);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);
        assertEq(messageQueue.pendingQueueIndex(), 2);
        hevm.stopPrank();
        for (uint256 i = 0; i < 2; ++i) {
            assertBoolEq(messageQueue.isMessageSkipped(i), true);
            assertBoolEq(messageQueue.isMessageDropped(i), false);
        }
        hevm.expectEmit(false, false, false, true);
        emit OnDropMessageCalled(new bytes(0));
        l1Messenger.dropMessage(address(this), address(0), 0, 0, new bytes(0));
        for (uint256 i = 0; i < 2; ++i) {
            assertBoolEq(messageQueue.isMessageSkipped(i), true);
            assertBoolEq(messageQueue.isMessageDropped(i), true);
        }

        // send one message with nonce 2 and replay 3 times
        l1Messenger.sendMessage(address(0), 0, new bytes(0), DEFAULT_GAS_LIMIT);
        assertEq(messageQueue.nextCrossDomainMessageIndex(), 3);
        for (uint256 i = 0; i < 3; i++) {
            l1Messenger.replayMessage(address(this), address(0), 0, 2, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
        }
        assertEq(messageQueue.nextCrossDomainMessageIndex(), 6);

        // only first 3 are skipped
        hevm.startPrank(address(rollup));
        messageQueue.popCrossDomainMessage(2, 4, 0x7);
        messageQueue.finalizePoppedCrossDomainMessage(6);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 6);
        assertEq(messageQueue.pendingQueueIndex(), 6);
        hevm.stopPrank();
        for (uint256 i = 2; i < 6; i++) {
            assertBoolEq(messageQueue.isMessageSkipped(i), i < 5);
            assertBoolEq(messageQueue.isMessageDropped(i), false);
        }

        // drop non-skipped message, revert
        hevm.expectRevert("drop non-skipped message");
        l1Messenger.dropMessage(address(this), address(0), 0, 2, new bytes(0));

        // send one message with nonce 6 and replay 4 times
        l1Messenger.sendMessage(address(0), 0, new bytes(0), DEFAULT_GAS_LIMIT);
        for (uint256 i = 0; i < 4; i++) {
            l1Messenger.replayMessage(address(this), address(0), 0, 6, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
        }
        assertEq(messageQueue.nextCrossDomainMessageIndex(), 11);

        // skip all 5 messages
        hevm.startPrank(address(rollup));
        messageQueue.popCrossDomainMessage(6, 5, 0x1f);
        messageQueue.finalizePoppedCrossDomainMessage(11);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 11);
        assertEq(messageQueue.pendingQueueIndex(), 11);
        hevm.stopPrank();
        for (uint256 i = 6; i < 11; ++i) {
            assertBoolEq(messageQueue.isMessageSkipped(i), true);
            assertBoolEq(messageQueue.isMessageDropped(i), false);
        }
        hevm.expectEmit(false, false, false, true);
        emit OnDropMessageCalled(new bytes(0));
        l1Messenger.dropMessage(address(this), address(0), 0, 6, new bytes(0));
        for (uint256 i = 6; i < 11; ++i) {
            assertBoolEq(messageQueue.isMessageSkipped(i), true);
            assertBoolEq(messageQueue.isMessageDropped(i), true);
        }

        // Message already dropped, revert
        hevm.expectRevert("Message already dropped");
        l1Messenger.dropMessage(address(this), address(0), 0, 0, new bytes(0));
        hevm.expectRevert("Message already dropped");
        l1Messenger.dropMessage(address(this), address(0), 0, 6, new bytes(0));

        // replay dropped message, revert
        hevm.expectRevert("Message already dropped");
        l1Messenger.replayMessage(address(this), address(0), 0, 0, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
        hevm.expectRevert("Message already dropped");
        l1Messenger.replayMessage(address(this), address(0), 0, 6, new bytes(0), DEFAULT_GAS_LIMIT, address(0));
    }

    function testRelayMessageWithProof() external {
        rollup.addProver(address(0));
        bytes memory batchHeader1 = new bytes(193);
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory blobDataProof =
        // solhint-disable-next-line max-line-length
            hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        assembly {
            mstore8(add(batchHeader1, 0x20), 3) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            // dataHash
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51)
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), 0) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        batchHeader1[1] = bytes1(uint8(0)); // change back
        bytes32 withdrawRoot = 0x222854db53c4515941d8fef2e5367f5fe781fa56506bb1463985c15bfa4a59da;
        assertBoolEq(rollup.isBatchFinalized(1), false);
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(uint256(2)), withdrawRoot, new bytes(0));

        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), true);

        bytes32 withdrawRootBatch1 = rollup.withdrawRoots(1);
        assertEq(withdrawRoot, withdrawRootBatch1, "withdraw root");

        // generated with off-chain merkle proof generator
        // bytes memory proofForThirdMessageInTree =
        // // solhint-disable-next-line max-line-length
        //hex"00000000000000000000000000000000000000000000000000000000000000005bc
        //8d719dee759f579606f5e9326010c9b4f1c89d2579636761a6bd37e348f4e";
        // // IL1T1Messenger.L2MessageProof memory messageProof =
        // //     IL1T1Messenger.L2MessageProof({ batchIndex: 1, merkleProof: proofForThirdMessageInTree });
        uint256 nonce = 2;
        uint256 msgValue = 1;
        bytes memory message = new bytes(0);
        address from = address(0xbeef);
        // does not revert
        l1Messenger.relayMessageWithProof(from, address(0), msgValue, nonce, message);
    }

    function onDropMessage(bytes memory message) external payable {
        emit OnDropMessageCalled(message);
    }
}
