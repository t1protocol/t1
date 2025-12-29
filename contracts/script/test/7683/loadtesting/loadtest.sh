#!/bin/bash

# Suppress Foundry nightly warning
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# Source env
if [[ -f ".env" ]]; then
    source .env
fi

# Number of times to run the script
RUN_COUNT=$1

# Check if RUN_COUNT is provided and is a positive integer
if [[ -z "$RUN_COUNT" || ! "$RUN_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: Please provide a valid number of runs as the first argument."
    exit 1
fi

# Array of possible directions
DIRECTIONS=("arb-to-base" "base-to-arb")

# Array of possible token pairs
TOKEN_PAIRS=("usdc-usdc" "weth-weth" "usdc-weth" "weth-usdc")

# Loop to run the forge script RUN_COUNT times
for ((i=1; i<=RUN_COUNT; i++))
do
    # Randomly select a direction
    DIRECTION=${DIRECTIONS[$RANDOM % ${#DIRECTIONS[@]}]}
    
    # Randomly select a token pair
    TOKEN_PAIR=${TOKEN_PAIRS[$RANDOM % ${#TOKEN_PAIRS[@]}]}
    
    # Select RPC URL based on direction
    if [[ "$DIRECTION" == "arb-to-base" ]]; then
        RPC_URL=$ARBITRUM_RPC
    else
        RPC_URL=$BASE_RPC
    fi
    
    echo "Running script $i/$RUN_COUNT in direction: $DIRECTION with token pair: $TOKEN_PAIR"
    
    forge script ./script/test/7683/loadtesting/loadtest.s.sol:LoadTest \
        --rpc-url "$RPC_URL" \
        --broadcast \
        --private-key "$ALICE_PRIVATE_KEY" \
        --sig "run(string,string)" "$DIRECTION" "$TOKEN_PAIR"
done
