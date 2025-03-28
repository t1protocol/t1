// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { L2MessageQueue } from "../L2/predeploys/L2MessageQueue.sol";

contract L2MessageQueueTest is DSTestPlus {
    L2MessageQueue internal queue;

    function setUp() public {
        queue = new L2MessageQueue(address(this));
        queue.initialize(address(this));
    }

    function testConstructor() external {
        assertEq(queue.messenger(), address(this));
        assertEq(queue.nextMessageIndex(), 0);
    }

    function testPassMessageFailed() external {
        // not messenger
        hevm.startPrank(address(0));
        hevm.expectRevert("only messenger");
        queue.appendMessage(bytes32(0));
        hevm.stopPrank();
    }

    function testPassMessageOnceSuccess(bytes32 _message) external {
        queue.appendMessage(_message);
        assertEq(queue.nextMessageIndex(), 1);
        assertEq(queue.branches(0), _message);
        assertEq(queue.messageRoot(), _message);
    }

    function testPassMessageSuccess() external {
        queue.appendMessage(bytes32(uint256(1)));
        assertEq(queue.nextMessageIndex(), 1);
        assertEq(queue.branches(0), bytes32(uint256(1)));
        assertEq(queue.messageRoot(), bytes32(uint256(1)));

        queue.appendMessage(bytes32(uint256(2)));
        assertEq(queue.nextMessageIndex(), 2);
        assertEq(
            queue.branches(1), bytes32(uint256(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0))
        );
        assertEq(
            queue.messageRoot(), bytes32(uint256(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0))
        );

        queue.appendMessage(bytes32(uint256(3)));
        assertEq(queue.nextMessageIndex(), 3);
        assertEq(
            queue.branches(2), bytes32(uint256(0x222ff5e0b5877792c2bc1670e2ccd0c2c97cd7bb1672a57d598db05092d3d72c))
        );
        assertEq(
            queue.messageRoot(), bytes32(uint256(0x222ff5e0b5877792c2bc1670e2ccd0c2c97cd7bb1672a57d598db05092d3d72c))
        );

        queue.appendMessage(bytes32(uint256(4)));
        assertEq(queue.nextMessageIndex(), 4);
        assertEq(
            queue.branches(2), bytes32(uint256(0xa9bb8c3f1f12e9aa903a50c47f314b57610a3ab32f2d463293f58836def38d36))
        );
        assertEq(
            queue.messageRoot(), bytes32(uint256(0xa9bb8c3f1f12e9aa903a50c47f314b57610a3ab32f2d463293f58836def38d36))
        );
    }

    function testSetGasOracle() external {
        // non-owner cannot set gas oracle
        hevm.startPrank(address(0));
        hevm.expectRevert("caller is not the owner");
        queue.setGasOracle(1, address(0xdead));
        hevm.stopPrank();

        // owner can set gas oracle
        uint64 chainId = 1;
        address oracle = address(0xbeef);
        queue.setGasOracle(chainId, oracle);
        assertEq(queue.gasOraclesByChain(chainId), oracle);

        // can update existing oracle
        address newOracle = address(0xcafe);
        queue.setGasOracle(chainId, newOracle);
        assertEq(queue.gasOraclesByChain(chainId), newOracle);

        // can set for different chain IDs
        uint64 chainId2 = 2;
        address oracle2 = address(0xdead);
        queue.setGasOracle(chainId2, oracle2);
        assertEq(queue.gasOraclesByChain(chainId2), oracle2);
        // original chain ID oracle unchanged
        assertEq(queue.gasOraclesByChain(chainId), newOracle);
    }
}
