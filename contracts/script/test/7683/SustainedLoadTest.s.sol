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

/**
 * @title SustainedLoadTest
 * @dev Sustained load testing script for 7683 contracts that sends n transactions
 * every t seconds for a configurable duration. Supports both Arbitrum->Base and Base->Arbitrum flows.
 */
contract SustainedLoadTest is Script {
    // Configuration from environment variables
    uint256 public constant DEFAULT_TRANSACTIONS_PER_BATCH = 5;
    uint256 public constant DEFAULT_INTERVAL_SECONDS = 60; // 1 minute
    uint256 public constant DEFAULT_DURATION_SECONDS = 600; // 10 minutes
    uint256 public constant AMOUNT_IN = 10; // 0.00001 USDT (assuming 6 decimals)

    // Test state
    struct TestSession {
        uint256 startTime;
        uint256 endTime;
        uint256 totalBatches;
        uint256 transactionsPerBatch;
        uint256 intervalMinutes;
        bool isActive;
    }

    struct BatchResult {
        uint256 batchNumber;
        uint256 timestamp;
        uint256 successCount;
        uint256 failureCount;
        bytes32[] orderIds;
    }

    TestSession public currentSession;
    BatchResult[] public batchResults;
    uint256 public totalTransactions;
    uint256 public totalSuccesses;
    uint256 public totalFailures;
    uint256 public nonceCounter;

    event SessionStarted(uint256 startTime, uint256 endTime, uint256 transactionsPerBatch, uint256 intervalSeconds);
    event BatchCompleted(uint256 batchNumber, uint256 successCount, uint256 failureCount);
    event SessionEnded(uint256 totalTransactions, uint256 totalSuccesses, uint256 totalFailures);
    event TransactionSent(bytes32 indexed orderId, uint256 batchNumber, bool success);

    function run() external {
        // Get configuration from environment
        uint256 txsPerBatch = vm.envOr("SUSTAINED_TXS_PER_BATCH", uint256(DEFAULT_TRANSACTIONS_PER_BATCH));
        uint256 intervalSeconds = vm.envOr("SUSTAINED_INTERVAL_SECONDS", uint256(DEFAULT_INTERVAL_SECONDS));
        uint256 durationSeconds = vm.envOr("SUSTAINED_DURATION_SECONDS", uint256(DEFAULT_DURATION_SECONDS));
        string memory testDirection = vm.envOr("LOAD_TEST_DIRECTION", string("arbitrum_to_base"));

        console2.log("=== STARTING SUSTAINED LOAD TEST ===");
        console2.log("Transactions per batch: %d", txsPerBatch);
        console2.log("Interval (seconds): %d", intervalSeconds);
        console2.log("Duration (seconds): %d", durationSeconds);
        console2.log("Test direction: %s", testDirection);
        console2.log("ARB_T1_PULL_BASED_7683_PROXY_ADDR: %s", vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR"));
        console2.log("BASE_T1_PULL_BASED_7683_PROXY_ADDR: %s", vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR"));
        console2.log("ARBITRUM_SEPOLIA_USDT_ADDR: %s", vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));
        console2.log("BASE_SEPOLIA_USDT_ADDR: %s", vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
        console2.log("ALICE_ADDRESS: %s", vm.addr(vm.envUint("ALICE_PRIVATE_KEY")));

        // Validate configuration
        require(txsPerBatch > 0, "Transactions per batch must be > 0");
        require(intervalSeconds > 0, "Interval must be > 0");
        require(durationSeconds > 0, "Duration must be > 0");

        // Initialize session
        currentSession = TestSession({
            startTime: 0, // Not used for timing in script
            endTime: durationSeconds, // Duration in seconds
            totalBatches: durationSeconds / intervalSeconds,
            transactionsPerBatch: txsPerBatch,
            intervalMinutes: intervalSeconds / 60, // Convert to minutes for compatibility
            isActive: true
        });

        // Reset counters
        delete batchResults;
        totalTransactions = 0;
        totalSuccesses = 0;
        totalFailures = 0;
        nonceCounter = 0;

        emit SessionStarted(currentSession.startTime, currentSession.endTime, txsPerBatch, intervalSeconds);

        // Execute sustained load test based on direction
        if (keccak256(bytes(testDirection)) == keccak256(bytes("arbitrum_to_base"))) {
            _runSustainedArbitrumToBaseTest();
        } else if (keccak256(bytes(testDirection)) == keccak256(bytes("base_to_arbitrum"))) {
            _runSustainedBaseToArbitrumTest();
        } else {
            revert("Invalid test direction. Use 'arbitrum_to_base' or 'base_to_arbitrum'");
        }

        // Mark session as ended
        currentSession.isActive = false;

        // Print final results
        console2.log("=== SUSTAINED LOAD TEST COMPLETE ===");
        console2.log("Total transactions: %d", totalTransactions);
        console2.log("Total successes: %d", totalSuccesses);
        console2.log("Total failures: %d", totalFailures);
        console2.log("Success rate: %d%%", totalTransactions > 0 ? (totalSuccesses * 100) / totalTransactions : 0);
        console2.log("Total batches: %d", batchResults.length);
        emit SessionEnded(totalTransactions, totalSuccesses, totalFailures);
    }

    function _runSustainedArbitrumToBaseTest() internal {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        T1ERC7683 l1_7683 = T1ERC7683(vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR"));
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Approve tokens once at the beginning
        vm.startBroadcast(alicePk);
        ERC20 inputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));
        inputToken.approve(address(l1_7683), type(uint256).max);
        vm.stopBroadcast();

        console2.log("Starting sustained Arbitrum -> Base load test with initial nonce: %d", nonceCounter);

        uint256 batchNumber = 0;
        while (batchNumber < currentSession.totalBatches && currentSession.isActive) {
            batchNumber++;
            _executeBatchArbitrumToBase(l1_7683, alicePk, alice, batchNumber);
            // Wait for next interval (unless it's the last batch)
            if (batchNumber < currentSession.totalBatches) {
                uint256 waitTime = currentSession.intervalMinutes * 60;
                console2.log("Waiting %d seconds for next batch...", waitTime);
                vm.sleep(waitTime * 1000); // Convert to milliseconds
            }
        }
    }

    function _runSustainedBaseToArbitrumTest() internal {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        T1ERC7683 l1_7683 = T1ERC7683(vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR"));
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Approve tokens once at the beginning
        vm.startBroadcast(alicePk);
        ERC20 inputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
        inputToken.approve(address(l1_7683), type(uint256).max);
        vm.stopBroadcast();

        console2.log("Starting sustained Base -> Arbitrum load test with initial nonce: %d", nonceCounter);

        uint256 batchNumber = 0;
        while (batchNumber < currentSession.totalBatches && currentSession.isActive) {
            batchNumber++;
            _executeBatchBaseToArbitrum(l1_7683, alicePk, alice, batchNumber);
            // Wait for next interval (unless it's the last batch)
            if (batchNumber < currentSession.totalBatches) {
                uint256 waitTime = currentSession.intervalMinutes * 60;
                console2.log("Waiting %d seconds for next batch...", waitTime);
                vm.sleep(waitTime * 1000); // Convert to milliseconds
            }
        }
    }

    function _executeBatchArbitrumToBase(
        T1ERC7683 l1_7683,
        uint256 alicePk,
        address alice,
        uint256 batchNumber
    ) internal {
        console2.log("=== Executing Batch %d ===", batchNumber);
        bytes32[] memory orderIds = new bytes32[](currentSession.transactionsPerBatch);
        uint256 batchSuccesses = 0;
        uint256 batchFailures = 0;

        for (uint256 i = 0; i < currentSession.transactionsPerBatch; i++) {
            // Find a valid (unused) nonce
            uint256 maxAttempts = 1000; // Safety limit to prevent infinite loop
            uint256 attempts = 0;
            while (!l1_7683.isValidNonce(alice, nonceCounter) && attempts < maxAttempts) {
                nonceCounter++;
                attempts++;
            }
            if (attempts >= maxAttempts) {
                console2.log("Transaction %d failed: Could not find valid nonce", i);
                batchFailures++;
                totalFailures++;
                continue;
            }

            vm.startBroadcast(alicePk);
            ERC20 inputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));
            ERC20 outputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));

            // Log allowance and balance
            uint256 allowance = inputToken.allowance(alice, address(l1_7683));
            uint256 balance = inputToken.balanceOf(alice);
            console2.log("Transaction %d: Allowance: %d, Balance: %d", i, allowance, balance);

            // Log Ethereum nonce
            uint256 ethNonce = vm.getNonce(alice);
            console2.log("Transaction %d: Ethereum nonce: %d, SenderNonce: %d", i, ethNonce, nonceCounter);

            // Prepare order data
            OrderData memory orderData = OrderData({
                sender: TypeCasts.addressToBytes32(alice),
                recipient: TypeCasts.addressToBytes32(alice),
                inputToken: TypeCasts.addressToBytes32(address(inputToken)),
                outputToken: TypeCasts.addressToBytes32(address(outputToken)),
                amountIn: AMOUNT_IN,
                minAmountOut: AMOUNT_IN * 9 / 10,
                senderNonce: uint32(nonceCounter),
                originDomain: uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID),
                destinationDomain: uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID),
                destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR")),
                fillDeadline: uint32(1800), // 30 minutes
                closedAuction: true,
                data: new bytes(0)
            });

            bytes memory encodedOrder = OrderEncoder.encode(orderData);
            OnchainCrossChainOrder memory order = _prepareOnchainOrder(encodedOrder, uint32(1800), OrderEncoder.orderDataType());

            // Try submitting the order
            try l1_7683.open(order) {
                bytes32 id = OrderEncoder.id(orderData);
                orderIds[i] = id;
                batchSuccesses++;
                totalSuccesses++;
                console2.log("Transaction %d succeeded, Order ID: %s", i, vm.toString(id));
                emit TransactionSent(id, batchNumber, true);
                nonceCounter++; // Increment nonce only on success
            } catch Error(string memory reason) {
                console2.log("Transaction %d failed: %s", i, reason);
                batchFailures++;
                totalFailures++;
                orderIds[i] = bytes32(0);
                emit TransactionSent(bytes32(0), batchNumber, false);
            } catch {
                console2.log("Transaction %d failed with unknown error", i);
                batchFailures++;
                totalFailures++;
                orderIds[i] = bytes32(0);
                emit TransactionSent(bytes32(0), batchNumber, false);
            }

            vm.stopBroadcast();
            totalTransactions++;

            // Wait for transaction confirmation or add delay
            vm.sleep(500); // 500ms delay
        }

        // Record batch results
        batchResults.push(BatchResult({
            batchNumber: batchNumber,
            timestamp: 0,
            successCount: batchSuccesses,
            failureCount: batchFailures,
            orderIds: orderIds
        }));
        console2.log("Batch %d completed: %d successes, %d failures", batchNumber, batchSuccesses, batchFailures);
        emit BatchCompleted(batchNumber, batchSuccesses, batchFailures);
    }

    function _executeBatchBaseToArbitrum(
        T1ERC7683 l1_7683,
        uint256 alicePk,
        address alice,
        uint256 batchNumber
    ) internal {
        console2.log("=== Executing Batch %d ===", batchNumber);
        bytes32[] memory orderIds = new bytes32[](currentSession.transactionsPerBatch);
        uint256 batchSuccesses = 0;
        uint256 batchFailures = 0;

        for (uint256 i = 0; i < currentSession.transactionsPerBatch; i++) {
            // Find a valid (unused) nonce
            uint256 maxAttempts = 1000; // Safety limit to prevent infinite loop
            uint256 attempts = 0;
            while (!l1_7683.isValidNonce(alice, nonceCounter) && attempts < maxAttempts) {
                nonceCounter++;
                attempts++;
            }
            if (attempts >= maxAttempts) {
                console2.log("Transaction %d failed: Could not find valid nonce", i);
                batchFailures++;
                totalFailures++;
                continue;
            }

            vm.startBroadcast(alicePk);
            ERC20 inputToken = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
            ERC20 outputToken = ERC20(vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR"));

            // Log allowance and balance
            uint256 allowance = inputToken.allowance(alice, address(l1_7683));
            uint256 balance = inputToken.balanceOf(alice);
            console2.log("Transaction %d: Allowance: %d, Balance: %d", i, allowance, balance);

            // Log Ethereum nonce
            uint256 ethNonce = vm.getNonce(alice);
            console2.log("Transaction %d: Ethereum nonce: %d, SenderNonce: %d", i, ethNonce, nonceCounter);

            // Prepare order data
            OrderData memory orderData = OrderData({
                sender: TypeCasts.addressToBytes32(alice),
                recipient: TypeCasts.addressToBytes32(alice),
                inputToken: TypeCasts.addressToBytes32(address(inputToken)),
                outputToken: TypeCasts.addressToBytes32(address(outputToken)),
                amountIn: AMOUNT_IN,
                minAmountOut: AMOUNT_IN * 9 / 10,
                senderNonce: uint32(nonceCounter),
                originDomain: uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID),
                destinationDomain: uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID),
                destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR")),
                fillDeadline: uint32(1800), // 30 minutes
                closedAuction: true,
                data: new bytes(0)
            });

            bytes memory encodedOrder = OrderEncoder.encode(orderData);
            OnchainCrossChainOrder memory order = _prepareOnchainOrder(encodedOrder, uint32(1800), OrderEncoder.orderDataType());

            // Try submitting the order
            try l1_7683.open(order) {
                bytes32 id = OrderEncoder.id(orderData);
                orderIds[i] = id;
                batchSuccesses++;
                totalSuccesses++;
                console2.log("Transaction %d succeeded, Order ID: %s", i, vm.toString(id));
                emit TransactionSent(id, batchNumber, true);
                nonceCounter++; // Increment nonce only on success
            } catch Error(string memory reason) {
                console2.log("Transaction %d failed: %s", i, reason);
                batchFailures++;
                totalFailures++;
                orderIds[i] = bytes32(0);
                emit TransactionSent(bytes32(0), batchNumber, false);
            } catch {
                console2.log("Transaction %d failed with unknown error", i);
                batchFailures++;
                totalFailures++;
                orderIds[i] = bytes32(0);
                emit TransactionSent(bytes32(0), batchNumber, false);
            }

            vm.stopBroadcast();
            totalTransactions++;

            // Wait for transaction confirmation or add delay
            vm.sleep(500); // 500ms delay
        }

        // Record batch results
        batchResults.push(BatchResult({
            batchNumber: batchNumber,
            timestamp: 0,
            successCount: batchSuccesses,
            failureCount: batchFailures,
            orderIds: orderIds
        }));
        console2.log("Batch %d completed: %d successes, %d failures", batchNumber, batchSuccesses, batchFailures);
        emit BatchCompleted(batchNumber, batchSuccesses, batchFailures);
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
        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: orderData
        });
    }

    // Utility functions for analysis
    function getBatchResults() external view returns (BatchResult[] memory) {
        return batchResults;
    }

    function getCurrentSession() external view returns (TestSession memory) {
        return currentSession;
    }

    function getOverallSuccessRate() external view returns (uint256) {
        if (totalTransactions == 0) return 0;
        return (totalSuccesses * 100) / totalTransactions;
    }

    function getAverageBatchSuccessRate() external view returns (uint256) {
        if (batchResults.length == 0) return 0;
        uint256 totalBatchSuccesses = 0;
        uint256 totalBatchTransactions = 0;
        for (uint256 i = 0; i < batchResults.length; i++) {
            totalBatchSuccesses += batchResults[i].successCount;
            totalBatchTransactions += batchResults[i].successCount + batchResults[i].failureCount;
        }
        if (totalBatchTransactions == 0) return 0;
        return (totalBatchSuccesses * 100) / totalBatchTransactions;
    }

    // Emergency stop function
    function emergencyStop() external {
        require(currentSession.isActive, "No active session to stop");
        currentSession.isActive = false;
        console2.log("Emergency stop triggered - session ended");
    }
}

interface T1ERC7683 {
    function open(OnchainCrossChainOrder memory order) external payable;
    function isValidNonce(address _from, uint256 _nonce) external view returns (bool);
}