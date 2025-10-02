#!/bin/bash

# 7683 Load Test Runner Script
# Usage: 
#   Burst Mode: ./run-load-test.sh burst [max_transactions] [direction]
#   Sustained Mode: ./run-load-test.sh sustained [txs_per_batch] [interval] [duration] [direction]
# 
# Examples:
#   ./run-load-test.sh burst 50 arbitrum_to_base
#   ./run-load-test.sh sustained 5 2m 20m base_to_arbitrum
#   ./run-load-test.sh sustained 3 30s 5m arbitrum_to_base
#   ./run-load-test.sh burst 25  # defaults to arbitrum_to_base

# Load environment variables from .env file
load_env() {
    # Look for .env file in current directory, then parent directories
    local env_file=""
    local current_dir="$(pwd)"
    
    # Check current directory first
    if [ -f ".env" ]; then
        env_file=".env"
    # Check contracts directory (if running from script directory)
    elif [ -f "../.env" ]; then
        env_file="../.env"
    # Check root directory (if running from contracts/script/test/7683)
    elif [ -f "../../../.env" ]; then
        env_file="../../../.env"
    fi
    
    if [ -n "$env_file" ]; then
        echo "Loading environment variables from: $env_file"
        # Export variables from .env file, ignoring comments and empty lines
        set -a  # automatically export all variables
        source "$env_file"
        set +a  # stop automatically exporting
        echo "Environment variables loaded successfully"
    else
        echo "Warning: No .env file found in current directory or parent directories"
        echo "Make sure you have a .env file with required variables"
    fi
}

# Function to parse time units (e.g., "30s", "2m", "1h")
parse_time() {
    local time_str="$1"
    local time_value="${time_str%[smh]}"
    local time_unit="${time_str: -1}"
    
    case "$time_unit" in
        s|S)
            echo "$time_value"
            ;;
        m|M)
            echo $((time_value * 60))
            ;;
        h|H)
            echo $((time_value * 3600))
            ;;
        *)
            # If no unit specified, assume seconds
            echo "$time_value"
            ;;
    esac
}

# Function to display usage
show_usage() {
    echo "Usage:"
    echo "  Burst Mode:    $0 burst [max_transactions] [direction]"
    echo "  Sustained Mode: $0 sustained [txs_per_batch] [interval] [duration] [direction]"
    echo ""
    echo "Examples:"
    echo "  $0 burst 50 arbitrum_to_base"
    echo "  $0 sustained 5 2m 20m base_to_arbitrum"
    echo "  $0 sustained 3 30s 5m arbitrum_to_base"
    echo "  $0 sustained 10 1h 2h arbitrum_to_base"
    echo "  $0 burst 25  # defaults to arbitrum_to_base"
    echo ""
    echo "Time units:"
    echo "  s = seconds (e.g., 30s)"
    echo "  m = minutes (e.g., 2m)"
    echo "  h = hours (e.g., 1h)"
    echo ""
    echo "Directions: arbitrum_to_base, base_to_arbitrum"
}

# Load environment variables first
load_env

# Check if at least one argument is provided
if [ $# -lt 1 ]; then
    echo "Error: Missing test mode argument"
    show_usage
    exit 1
fi

MODE=$1

# Validate mode
if [[ "$MODE" != "burst" && "$MODE" != "sustained" ]]; then
    echo "Error: Invalid mode. Use 'burst' or 'sustained'"
    show_usage
    exit 1
fi

# Set default RPC URL based on direction (will be overridden if direction is provided)
DEFAULT_RPC="arbitrum_sepolia"

if [ "$MODE" = "burst" ]; then
    # Burst mode configuration
    MAX_TRANSACTIONS=${2:-10}
    DIRECTION=${3:-arbitrum_to_base}
    
    # Validate direction
    if [[ "$DIRECTION" != "arbitrum_to_base" && "$DIRECTION" != "base_to_arbitrum" ]]; then
        echo "Error: Invalid direction. Use 'arbitrum_to_base' or 'base_to_arbitrum'"
        exit 1
    fi
    
    # Validate max transactions
    if ! [[ "$MAX_TRANSACTIONS" =~ ^[0-9]+$ ]] || [ "$MAX_TRANSACTIONS" -lt 1 ]; then
        echo "Error: Max transactions must be a positive integer"
        exit 1
    fi
    
    # Set RPC URL based on direction
    if [[ "$DIRECTION" == "arbitrum_to_base" ]]; then
        RPC_URL="arbitrum_sepolia"
        VERIFIER_URL="https://api-sepolia.arbiscan.io/api"
        API_KEY="$ARBISCAN_API_KEY"
    else
        RPC_URL="base_sepolia"
        VERIFIER_URL="https://api-sepolia.basescan.org/api"
        API_KEY="$BASESCAN_API_KEY"
    fi
    
    echo "=========================================="
    echo "Starting 7683 BURST Load Test"
    echo "=========================================="
    echo "Mode: Burst"
    echo "Max Transactions: $MAX_TRANSACTIONS"
    echo "Direction: $DIRECTION"
    echo "RPC URL: $RPC_URL"
    echo "Timestamp: $(date)"
    echo "=========================================="
    
    # Set environment variables for the test
    export LOAD_TEST_MAX_TRANSACTIONS=$MAX_TRANSACTIONS
    export LOAD_TEST_DIRECTION=$DIRECTION
    
    SCRIPT_NAME="BurstLoadTest"
    
elif [ "$MODE" = "sustained" ]; then
    # Sustained mode configuration
    TXS_PER_BATCH=${2:-5}
    INTERVAL_STR=${3:-1m}
    DURATION_STR=${4:-10m}
    DIRECTION=${5:-arbitrum_to_base}
    
    # Parse time strings to seconds
    INTERVAL_SECONDS=$(parse_time "$INTERVAL_STR")
    DURATION_SECONDS=$(parse_time "$DURATION_STR")
    
    # Validate direction
    if [[ "$DIRECTION" != "arbitrum_to_base" && "$DIRECTION" != "base_to_arbitrum" ]]; then
        echo "Error: Invalid direction. Use 'arbitrum_to_base' or 'base_to_arbitrum'"
        exit 1
    fi
    
    # Validate numeric inputs
    if ! [[ "$TXS_PER_BATCH" =~ ^[0-9]+$ ]] || [ "$TXS_PER_BATCH" -lt 1 ]; then
        echo "Error: Transactions per batch must be a positive integer"
        exit 1
    fi
    
    if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$INTERVAL_SECONDS" -lt 1 ]; then
        echo "Error: Invalid interval format. Use formats like '30s', '2m', '1h'"
        exit 1
    fi
    
    if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || [ "$DURATION_SECONDS" -lt 1 ]; then
        echo "Error: Invalid duration format. Use formats like '30s', '2m', '1h'"
        exit 1
    fi
    
    # Set RPC URL based on direction
    if [[ "$DIRECTION" == "arbitrum_to_base" ]]; then
        RPC_URL="arbitrum_sepolia"
        VERIFIER_URL="https://api-sepolia.arbiscan.io/api"
        API_KEY="$ARBISCAN_API_KEY"
    else
        RPC_URL="base_sepolia"
        VERIFIER_URL="https://api-sepolia.basescan.org/api"
        API_KEY="$BASESCAN_API_KEY"
    fi
    
    echo "=========================================="
    echo "Starting 7683 SUSTAINED Load Test"
    echo "=========================================="
    echo "Mode: Sustained"
    echo "Transactions per batch: $TXS_PER_BATCH"
    echo "Interval: $INTERVAL_STR ($INTERVAL_SECONDS seconds)"
    echo "Duration: $DURATION_STR ($DURATION_SECONDS seconds)"
    echo "Direction: $DIRECTION"
    echo "RPC URL: $RPC_URL"
    echo "Timestamp: $(date)"
    echo "=========================================="
    
    # Set environment variables for the test
    export SUSTAINED_TXS_PER_BATCH=$TXS_PER_BATCH
    export SUSTAINED_INTERVAL_SECONDS=$INTERVAL_SECONDS
    export SUSTAINED_DURATION_SECONDS=$DURATION_SECONDS
    export LOAD_TEST_DIRECTION=$DIRECTION
    
    SCRIPT_NAME="SustainedLoadTest"
fi

# Check if required API keys are set
if [ -z "$API_KEY" ]; then
    echo "Error: Required API key is not set in environment"
    if [[ "$DIRECTION" == "arbitrum_to_base" ]]; then
        echo "Please set ARBISCAN_API_KEY environment variable"
    else
        echo "Please set BASESCAN_API_KEY environment variable"
    fi
    exit 1
fi

# Run the Forge script
cd "$(dirname "$0")/../../.."
forge script ./script/test/7683/${SCRIPT_NAME}.s.sol:${SCRIPT_NAME} \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --verifier etherscan \
    --verifier-url $VERIFIER_URL \
    --etherscan-api-key $API_KEY \
    -vvv

echo "=========================================="
echo "Load test completed at: $(date)"
echo "=========================================="
