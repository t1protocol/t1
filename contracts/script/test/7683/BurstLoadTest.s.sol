// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";
import { T1ERC7683 } from "../../../src/7683/T1ERC7683.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";
import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

/**
 * @title BurstLoadTest
 * @dev Load testing script for 7683 contracts that sends a configurable number of transactions
 *      sequentially to avoid RPC rate limiting. Supports both Arbitrum->Base and Base->Arbitrum flows.
 */
contract BurstLoadTest is Script, DeploymentUtils {
    // Configuration from environment variables
    uint256 public constant MAX_TRANSACTIONS = 10; // Default, can be overridden by env var
    uint256 public constant AMOUNT_IN = 10; // 0.00001 USDT (assuming 6 decimals)

    // Test results tracking
    struct TestResult {
        bytes32 orderId;
        uint256 txHash;
        uint256 timestamp;
        bool success;
    }

    TestResult[] public results;
    uint256 public successCount;
    uint256 public failureCount;

    event TransactionSent(bytes32 indexed orderId, uint256 txHash, bool success);
    event LoadTestComplete(uint256 totalTransactions, uint256 successCount, uint256 failureCount);

    function run() external {
        // Get configuration from environment
        uint256 maxTxs = vm.envOr("LOAD_TEST_MAX_TRANSACTIONS", uint256(MAX_TRANSACTIONS));
        string memory testDirection = vm.envOr("LOAD_TEST_DIRECTION", string("arbitrum_to_base"));

        console2.log("Starting load test with", maxTxs, "transactions");
        console2.log("Test direction:", testDirection);

        // Reset counters
        delete results;
        successCount = 0;
        failureCount = 0;

        // Execute load test based on direction
        if (keccak256(bytes(testDirection)) == keccak256(bytes("arbitrum_to_base"))) {
            _runArbitrumToBaseLoadTest(maxTxs);
        } else if (keccak256(bytes(testDirection)) == keccak256(bytes("base_to_arbitrum"))) {
            _runBaseToArbitrumLoadTest(maxTxs);
        } else {
            revert("Invalid test direction. Use 'arbitrum_to_base' or 'base_to_arbitrum'");
        }

        // Print final results
        console2.log("=== BURST LOAD TEST COMPLETE ===");
        console2.log("Total transactions:", maxTxs);
        console2.log("Successful:", successCount);
        console2.log("Failed:", failureCount);
        console2.log("Success rate:", (successCount * 100) / maxTxs, "%");

        emit LoadTestComplete(maxTxs, successCount, failureCount);
    }

    function _runArbitrumToBaseLoadTest(uint256 maxTxs) internal {
        DeploymentUtils.selectMainnetOrSepoliaFork("arbitrum");

        T1ERC7683 l1_7683 = T1ERC7683(vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR"));
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Approve tokens once at the beginning
        vm.startBroadcast(alicePk);
        ERC20 inputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));
        inputToken.approve(address(l1_7683), type(uint256).max);
        vm.stopBroadcast();

        console2.log("Starting Arbitrum -> Base load test...");

        // Send transactions sequentially
        for (uint256 i = 0; i < maxTxs; i++) {
            _sendArbitrumToBaseTransaction(l1_7683, alicePk, alice, i);

            // Small delay to avoid overwhelming the RPC
            vm.sleep(100); // 100ms delay between transactions
        }
    }

    function _runBaseToArbitrumLoadTest(uint256 maxTxs) internal {
        DeploymentUtils.selectMainnetOrSepoliaFork("base");

        T1ERC7683 l1_7683 = T1ERC7683(vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR"));
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Approve tokens once at the beginning
        vm.startBroadcast(alicePk);
        ERC20 inputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
        inputToken.approve(address(l1_7683), type(uint256).max);
        vm.stopBroadcast();

        console2.log("Starting Base -> Arbitrum load test...");

        // Send transactions sequentially
        for (uint256 i = 0; i < maxTxs; i++) {
            _sendBaseToArbitrumTransaction(l1_7683, alicePk, alice, i);

            // Small delay to avoid overwhelming the RPC
            vm.sleep(100); // 100ms delay between transactions
        }
    }

    function _sendArbitrumToBaseTransaction(
        T1ERC7683 l1_7683,
        uint256 alicePk,
        address alice,
        uint256 transactionIndex // Renamed for clarity
    )
        internal
    {
        vm.startBroadcast(alicePk);

        ERC20 inputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));

        // Find the next valid nonce
        uint32 nextNonce = 0;
        while (l1_7683.usedNonces(alice, nextNonce) || !l1_7683.isValidNonce(alice, nextNonce)) {
            nextNonce++;
            require(nextNonce < type(uint32).max, "No valid nonce available");
        }

        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: AMOUNT_IN,
            minAmountOut: AMOUNT_IN * 9 / 10,
            senderNonce: nextNonce,
            originDomain: uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID),
            destinationDomain: uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID),
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR")),
            fillDeadline: uint32(1800),
            closedAuction: true,
            data: new bytes(0)
        });

        bytes memory encodedOrder = OrderEncoder.encode(orderData);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(encodedOrder, uint32(1800), OrderEncoder.orderDataType());

        // Call open with try-catch to handle reverts
        try l1_7683.open(order) {
            bytes32 id = OrderEncoder.id(orderData);
            results.push(
                TestResult({
                    orderId: id,
                    txHash: uint256(keccak256(abi.encodePacked(nextNonce, "burst_test"))),
                    timestamp: 0,
                    success: true
                })
            );
            emit TransactionSent(id, results[results.length - 1].txHash, true);
            successCount++;
        } catch Error(string memory reason) {
            results.push(TestResult({ orderId: OrderEncoder.id(orderData), txHash: 0, timestamp: 0, success: false }));
            failureCount++;
            emit TransactionSent(OrderEncoder.id(orderData), 0, false);
        }

        vm.stopBroadcast();
    }

    function _sendBaseToArbitrumTransaction(
        T1ERC7683 l1_7683,
        uint256 alicePk,
        address alice,
        uint256 transactionIndex
    )
        internal
    {
        vm.startBroadcast(alicePk);

        ERC20 inputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));

        // Find the next valid nonce
        uint32 nextNonce = 0;
        while (l1_7683.usedNonces(alice, nextNonce) || !l1_7683.isValidNonce(alice, nextNonce)) {
            nextNonce++;
            require(nextNonce < type(uint32).max, "No valid nonce available");
        }

        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: AMOUNT_IN,
            minAmountOut: AMOUNT_IN * 9 / 10,
            senderNonce: nextNonce,
            originDomain: uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID),
            destinationDomain: uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID),
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR")),
            fillDeadline: uint32(1800),
            closedAuction: true,
            data: new bytes(0)
        });

        bytes memory encodedOrder = OrderEncoder.encode(orderData);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(encodedOrder, uint32(1800), OrderEncoder.orderDataType());

        try l1_7683.open(order) {
            bytes32 id = OrderEncoder.id(orderData);
            results.push(
                TestResult({
                    orderId: id,
                    txHash: uint256(keccak256(abi.encodePacked(nextNonce, "burst_test"))),
                    timestamp: 0,
                    success: true
                })
            );
            emit TransactionSent(id, results[results.length - 1].txHash, true);
            successCount++;
        } catch Error(string memory reason) {
            results.push(TestResult({ orderId: OrderEncoder.id(orderData), txHash: 0, timestamp: 0, success: false }));
            failureCount++;
            emit TransactionSent(OrderEncoder.id(orderData), 0, false);
        }

        vm.stopBroadcast();
    }

    function _prepareOnchainOrder(
        bytes memory orderData,
        uint32 fillDeadline,
        bytes32 orderDataType
    )
        internal
        pure
        returns (OnchainCrossChainOrder memory)
    {
        return
            OnchainCrossChainOrder({ fillDeadline: fillDeadline, orderDataType: orderDataType, orderData: orderData });
    }

    // Utility functions for analysis
    function getResults() external view returns (TestResult[] memory) {
        return results;
    }

    function getSuccessRate() external view returns (uint256) {
        if (successCount + failureCount == 0) return 0;
        return (successCount * 100) / (successCount + failureCount);
    }
}
