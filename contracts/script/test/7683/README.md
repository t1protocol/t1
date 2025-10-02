# 7683 Load Testing Scripts

This directory contains load testing scripts for the 7683 cross-chain contracts.

## Scripts

### BurstLoadTest.s.sol
Sends a configurable number of transactions sequentially as fast as possible for burst load testing.

### SustainedLoadTest.s.sol
Sends n transactions every t minutes for a sustained load test over a configurable duration.

### run-load-test.sh
Shell script runner that can execute either burst or sustained load tests with proper configuration.

## Usage

### Prerequisites
- Ensure your `.env` file is properly configured with all required variables
- Make sure you have sufficient tokens for testing (USDT on both chains)
- Set the required API keys: `ARBISCAN_API_KEY` and `BASESCAN_API_KEY`

### Burst Load Testing

Send a specified number of transactions as fast as possible:

```bash
# Send 50 transactions from Arbitrum to Base
./run-load-test.sh burst 50 arbitrum_to_base

# Send 100 transactions from Base to Arbitrum
./run-load-test.sh burst 100 base_to_arbitrum

# Send 25 transactions (defaults to arbitrum_to_base)
./run-load-test.sh burst 25
```

### Sustained Load Testing

Send n transactions every t interval for a specified duration with flexible time units:

```bash
# Send 5 transactions every 2 minutes for 20 minutes (Arbitrum to Base)
./run-load-test.sh sustained 5 2m 20m arbitrum_to_base

# Send 10 transactions every 30 seconds for 5 minutes (Base to Arbitrum)
./run-load-test.sh sustained 10 30s 5m base_to_arbitrum

# Send 3 transactions every 1 hour for 2 hours
./run-load-test.sh sustained 3 1h 2h arbitrum_to_base

# Use defaults: 5 transactions every 1 minute for 10 minutes
./run-load-test.sh sustained
```

**Time Units:**
- `s` = seconds (e.g., `30s`)
- `m` = minutes (e.g., `2m`) 
- `h` = hours (e.g., `1h`)

## Environment Variables

### Required for Both Modes
- `ALICE_PRIVATE_KEY` - Private key for the test account
- `ARBISCAN_API_KEY` - API key for Arbitrum verification
- `BASESCAN_API_KEY` - API key for Base verification

### Required Contract Addresses
- `ARB_T1_PULL_BASED_7683_PROXY_ADDR` - Arbitrum 7683 contract
- `BASE_T1_PULL_BASED_7683_PROXY_ADDR` - Base 7683 contract
- `ARBITRUM_SEPOLIA_USDT_ADDR` - USDT on Arbitrum Sepolia
- `BASE_SEPOLIA_USDT_ADDR` - USDT on Base Sepolia

### Optional Configuration
- `LOAD_TEST_MAX_TRANSACTIONS` - Override default max transactions for burst mode
- `SUSTAINED_TXS_PER_BATCH` - Override default transactions per batch for sustained mode
- `SUSTAINED_INTERVAL_MINUTES` - Override default interval for sustained mode
- `SUSTAINED_DURATION_MINUTES` - Override default duration for sustained mode
- `LOAD_TEST_DIRECTION` - Override test direction (arbitrum_to_base or base_to_arbitrum)

## Test Flow

Both scripts follow the same basic flow:

1. **Setup**: Connect to the appropriate RPC and load contract addresses
2. **Token Approval**: Approve the maximum amount of USDT for the 7683 contract
3. **Transaction Execution**: 
   - Create cross-chain order data with unique nonces
   - Call `T1ERC7683.open()` with the order
   - Track success/failure rates
4. **Reporting**: Log results and emit events for analysis

## Monitoring

### Events Emitted
- `TransactionSent(bytes32 orderId, uint256 batchNumber, bool success)`
- `LoadTestComplete(uint256 totalTransactions, uint256 successCount, uint256 failureCount)` (burst mode)
- `BatchCompleted(uint256 batchNumber, uint256 successCount, uint256 failureCount)` (sustained mode)
- `SessionStarted/Ended` events (sustained mode)

### Console Output
- Real-time progress updates
- Success/failure counts
- Final statistics including success rates
- Error messages for failed transactions

## Rate Limiting Considerations

- **Burst Mode**: Includes 100ms delays between transactions to avoid overwhelming RPC endpoints
- **Sustained Mode**: Configurable intervals between batches to maintain sustained load
- Both modes send transactions sequentially to avoid RPC rate limits

## Emergency Controls

### Sustained Mode Emergency Stop
The sustained load test includes an `emergencyStop()` function that can be called to immediately halt an active test session.

## Example Test Scenarios

### Quick Burst Test
```bash
# Test with 20 transactions to verify basic functionality
./run-load-test.sh burst 20 arbitrum_to_base
```

### Stress Test
```bash
# Send 100 transactions to test system under load
./run-load-test.sh burst 100 arbitrum_to_base
```

### Long-term Stability Test
```bash
# Run for 2 hours with 3 transactions every 5 minutes
./run-load-test.sh sustained 3 5m 2h arbitrum_to_base
```

### High Frequency Test
```bash
# Send 10 transactions every 30 seconds for 10 minutes
./run-load-test.sh sustained 10 30s 10m arbitrum_to_base
```

### Very High Frequency Test
```bash
# Send 5 transactions every 10 seconds for 1 minute
./run-load-test.sh sustained 5 10s 1m arbitrum_to_base
```

## Troubleshooting

### Common Issues
1. **Insufficient tokens**: Ensure Alice's account has enough USDT on both chains
2. **RPC rate limits**: Increase delays in the script if you encounter rate limiting
3. **Contract not deployed**: Verify all contract addresses in your `.env` file
4. **API key issues**: Ensure your Etherscan/Blockscout API keys are valid

### Debug Mode
Use `-vvv` flag in the shell script for maximum verbosity to debug issues.

## Safety Notes

- These scripts send real transactions on testnets
- Monitor your test account balances
- Use appropriate delays to avoid overwhelming RPC endpoints
- Start with small transaction counts to verify functionality
