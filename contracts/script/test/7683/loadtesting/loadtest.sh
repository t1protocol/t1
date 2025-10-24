#!/bin/bash
# ===============================================
# T1ERC7683 Intent Settlement Script
# Random asset selection + timed transactions + random direction (Base <-> Arbitrum)
# Uses random uint32 nonce without validation, with retries for nonce collisions
# Limits transaction amounts to $0.001 USD equivalent for USDC and WETH
# Uses environment variables for chain-specific configs
# Matches Solidity OrderData struct with data field
# ===============================================
# Suppress Foundry nightly warning
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1
# Load environment variables from .env file if it exists
if [[ -f ".env" ]]; then
    source .env
fi
# CONFIGURATION
# Ensure required env vars are set
required_vars=("RPC_BASE" "RPC_ARB" "PROXY_BASE" "PROXY_ARB" "PRIVATE_KEY" "SENDER_ADDRESS" "RECIPIENT_ADDRESS")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "❌ Error: $var environment variable is not set" >&2
        exit 1
    fi
done
# Set default token addresses if not provided
USDC_BASE="${USDC_BASE:-0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913}"
USDC_ARB="${USDC_ARB:-0xaf88d065e77c8cC2239327C5EDb3A432268e5831}"
WETH_BASE="${WETH_BASE:-0x4200000000000000000000000000000000000006}"
WETH_ARB="${WETH_ARB:-0x82aF49447D8a07e3bd95BD0d56f35241523fBab1}"
# Chain domains (fixed)
DOMAIN_BASE=8453
DOMAIN_ARB=42161
# Counterparts (counterpart on the other chain)
COUNTERPART_BASE="${COUNTERPART_BASE:-$PROXY_ARB}" # Default to Arb proxy
COUNTERPART_ARB="${COUNTERPART_ARB:-$PROXY_BASE}" # Default to Base proxy
# ASSETS CONFIG (parallel arrays for asset names and amounts)
ASSET_NAMES=("USDC" "WETH")
ASSET_AMOUNTS=("1000" "400000000000") # 0.001 USDC (6 decimals, ~$0.001), 0.0000004 WETH (18 decimals, ~$0.001 at $2500/WETH)
ASSET_DECIMALS=("6" "18") # Decimals for each asset
# ORDER ENCODING
FILL_DEADLINE=1800 # 30 minutes, fixed to match Solidity
# Corrected ORDER_DATA_TYPE without field names
ORDER_DATA_TYPE=$(cast keccak "OrderData(bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,uint32,uint32,bytes32,uint32,bool,bytes)" | sed 's/^0x//')
ORDER_DATA_TYPE="0x$ORDER_DATA_TYPE"
# Validate ORDER_DATA_TYPE
if [[ ! "$ORDER_DATA_TYPE" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "❌ Error: Invalid ORDER_DATA_TYPE: $ORDER_DATA_TYPE" >&2
    exit 1
fi
echo "🔍 ORDER_DATA_TYPE: $ORDER_DATA_TYPE" >&2
encode_order_data() {
    local asset=$1
    local amount=$2
    local decimals=$3
    local origin_domain=$4
    local dest_domain=$5
    local counterpart=$6
    local nonce=$7
    local input_token_addr
    local output_token_addr
    case $asset in
        "USDC")
            if [[ $origin_domain -eq $DOMAIN_BASE ]]; then
                input_token_addr="$USDC_BASE"
            else
                input_token_addr="$USDC_ARB"
            fi
            if [[ $dest_domain -eq $DOMAIN_BASE ]]; then
                output_token_addr="$USDC_BASE"
            else
                output_token_addr="$USDC_ARB"
            fi
            ;;
        "WETH")
            if [[ $origin_domain -eq $DOMAIN_BASE ]]; then
                input_token_addr="$WETH_BASE"
            else
                input_token_addr="$WETH_ARB"
            fi
            if [[ $dest_domain -eq $DOMAIN_BASE ]]; then
                output_token_addr="$WETH_BASE"
            else
                output_token_addr="$WETH_ARB"
            fi
            ;;
        *)
            echo "❌ Invalid asset: $asset" >&2
            return 1
            ;;
    esac
    if [[ -z "$input_token_addr" || -z "$output_token_addr" ]]; then
        echo "❌ Error: Token addresses not set for $asset on origin $origin_domain -> dest $dest_domain" >&2
        return 1
    fi
    local sender_addr=$(cast to-bytes32 "$SENDER_ADDRESS")
    local recipient_addr=$(cast to-bytes32 "$RECIPIENT_ADDRESS")
    local counterpart_addr=$(cast to-bytes32 "$counterpart")
    local input_token=$(cast to-bytes32 "$input_token_addr")
    local output_token=$(cast to-bytes32 "$output_token_addr")
    local min_amount_out=$((amount * 90 / 100)) # Match Solidity: 90%
    # Validate sender address matches private key
    local derived_sender=$(cast wallet address --private-key "$PRIVATE_KEY")
    if [[ "$derived_sender" != "$SENDER_ADDRESS" ]]; then
        echo "❌ Error: SENDER_ADDRESS ($SENDER_ADDRESS) does not match address derived from PRIVATE_KEY ($derived_sender)" >&2
        return 1
    fi
    # Validate counterpart address matches contract's counterpart
    local contract_counterpart
    if [[ $origin_domain -eq $DOMAIN_BASE ]]; then
        contract_counterpart=$(cast call "$PROXY_BASE" "counterpart()(address)" --rpc-url "$RPC_BASE" 2>/dev/null)
    else
        contract_counterpart=$(cast call "$PROXY_ARB" "counterpart()(address)" --rpc-url "$RPC_ARB" 2>/dev/null)
    fi
    if [[ "$contract_counterpart" != "$counterpart" ]]; then
        echo "❌ Error: Counterpart ($counterpart) does not match contract's counterpart ($contract_counterpart) on origin $origin_domain" >&2
        return 1
    fi
    # Encode fields in the correct order per OrderData struct
    local args=(
        "$sender_addr"           # bytes32 sender
        "$recipient_addr"        # bytes32 recipient
        "$input_token"           # bytes32 inputToken
        "$output_token"          # bytes32 outputToken
        "$amount"                # uint256 amountIn
        "$min_amount_out"        # uint256 minAmountOut
        "$nonce"                 # uint256 senderNonce
        "$origin_domain"         # uint32 originDomain
        "$dest_domain"           # uint32 destinationDomain
        "$counterpart_addr"      # bytes32 destinationSettler
        "$FILL_DEADLINE"         # uint32 fillDeadline
        "true"                   # bool closedAuction
        "0x"                     # bytes data
    )
    for i in "${!args[@]}"; do
        if [[ -z "${args[$i]}" ]]; then
            echo "❌ Error: Argument $((i+1)) is empty or invalid" >&2
            return 1
        fi
    done
    echo "🔍 Encoding arguments: ${args[*]}" >&2
    # ABI-encode with the correct type string
    local encoded=$(cast abi-encode "encode(bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,uint32,uint32,bytes32,uint32,bool,bytes)" "${args[@]}" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "❌ Error: Failed to ABI encode arguments: ${args[*]}" >&2
        return 1
    fi
    # Validate hex string
    if [[ ! "$encoded" =~ ^0x[0-9a-fA-F]*$ ]]; then
        echo "❌ Error: Invalid hex string in ORDER_DATA: $encoded" >&2
        return 1
    fi
    local hex_length=${#encoded}
    echo "🔍 ORDER_DATA length: $((hex_length - 2)) bytes" >&2
    echo "$encoded"
    return 0
}
# Get random uint32 nonce
get_valid_nonce() {
    # Try od first
    local nonce=$(od -An -tu4 -N4 /dev/urandom 2>/dev/null)
    if [[ -z "$nonce" || ! "$nonce" =~ ^[0-9]+$ || "$nonce" -gt 4294967295 ]]; then
        echo "⚠️ od failed, falling back to RANDOM" >&2
        # Fallback to RANDOM
        nonce=$(( ($RANDOM << 16) + $RANDOM ))
        if [[ -z "$nonce" || ! "$nonce" =~ ^[0-9]+$ || "$nonce" -gt 4294967295 ]]; then
            echo "❌ Failed to generate random nonce with RANDOM" >&2
            return 1
        fi
    fi
    echo "🔍 Using random nonce: $nonce" >&2
    echo "$nonce"
    return 0
}
# MAIN SCRIPT
NUM_TXS="$1"
if [[ -z "$NUM_TXS" || ! "$NUM_TXS" =~ ^[0-9]+$ || "$NUM_TXS" -le 0 ]]; then
    echo "❌ Error: NUM_TXS must be a positive integer (got '$NUM_TXS')" >&2
    exit 1
fi
INTERVAL="${2:-0}" # Default: 0 (all at once)
if [[ ! "$INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: INTERVAL must be a non-negative integer (got '$INTERVAL')" >&2
    exit 1
fi
echo "🚀 Starting $NUM_TXS transactions (interval: ${INTERVAL}s)"
echo " Base: RPC $RPC_BASE | Proxy $PROXY_BASE | Counterpart $COUNTERPART_BASE | Domain $DOMAIN_BASE"
echo " Arb: RPC $RPC_ARB | Proxy $PROXY_ARB | Counterpart $COUNTERPART_ARB | Domain $DOMAIN_ARB"
echo " Sender: $SENDER_ADDRESS"
echo "================================================================"
# Validate asset arrays
if [[ ${#ASSET_NAMES[@]} -eq 0 || ${#ASSET_NAMES[@]} -ne ${#ASSET_AMOUNTS[@]} || ${#ASSET_NAMES[@]} -ne ${#ASSET_DECIMALS[@]} ]]; then
    echo "❌ Error: Asset arrays are misconfigured" >&2
    exit 1
fi
echo "📋 Available assets: ${ASSET_NAMES[*]}"
# Check sender's balances
for chain in "BASE" "ARB"; do
    RPC_VAR="RPC_$chain"
    USDC_VAR="USDC_$chain"
    WETH_VAR="WETH_$chain"
    RPC="${!RPC_VAR}"
    USDC="${!USDC_VAR}"
    WETH="${!WETH_VAR}"
    echo "🔍 Checking USDC balance for $SENDER_ADDRESS on $chain..."
    USDC_BALANCE=$(cast call "$USDC" "balanceOf(address)(uint256)" "$SENDER_ADDRESS" --rpc-url "$RPC" 2>/dev/null | sed 's/ \[.*\]//')
    if [[ $? -ne 0 || -z "$USDC_BALANCE" ]]; then
        echo "⚠️ Failed to query USDC balance on $chain" >&2
        continue
    fi
    USDC_REQUIRED_AMOUNT="1000" # 0.001 USDC
    if [[ ! "$USDC_BALANCE" =~ ^[0-9]+$ || "$USDC_BALANCE" -lt "$USDC_REQUIRED_AMOUNT" ]]; then
        echo "❌ Insufficient USDC balance on $chain: $USDC_BALANCE < $USDC_REQUIRED_AMOUNT" >&2
        exit 1
    fi
    echo "✅ USDC balance on $chain: $USDC_BALANCE (sufficient)"
    echo "🔍 Checking WETH balance for $SENDER_ADDRESS on $chain..."
    WETH_BALANCE=$(cast call "$WETH" "balanceOf(address)(uint256)" "$SENDER_ADDRESS" --rpc-url "$RPC" 2>/dev/null | sed 's/ \[.*\]//')
    if [[ $? -ne 0 || -z "$WETH_BALANCE" ]]; then
        echo "⚠️ Failed to query WETH balance on $chain" >&2
        continue
    fi
    WETH_REQUIRED_AMOUNT="400000000000" # 0.0000004 WETH
    if [[ ! "$WETH_BALANCE" =~ ^[0-9]+$ || "$WETH_BALANCE" -lt "$WETH_REQUIRED_AMOUNT" ]]; then
        echo "❌ Insufficient WETH balance on $chain: $WETH_BALANCE < $WETH_REQUIRED_AMOUNT" >&2
        exit 1
    fi
    echo "✅ WETH balance on $chain: $WETH_BALANCE (sufficient)"
done
# Execute transactions
for ((i=1; i<=NUM_TXS; i++)); do
    # Randomly select direction (0: Base -> Arb, 1: Arb -> Base)
    DIRECTION=$((RANDOM % 2))
    if [[ $DIRECTION -eq 0 ]]; then
        ORIGIN="BASE"
        DEST="ARB"
    else
        ORIGIN="ARB"
        DEST="BASE"
    fi
    RPC_VAR="RPC_$ORIGIN"
    RPC="${!RPC_VAR}"
    PROXY_VAR="PROXY_$ORIGIN"
    PROXY="${!PROXY_VAR}"
    DOMAIN_VAR="DOMAIN_$ORIGIN"
    LOCAL_DOMAIN="${!DOMAIN_VAR}"
    DEST_DOMAIN_VAR="DOMAIN_$DEST"
    DEST_DOMAIN="${!DEST_DOMAIN_VAR}"
    COUNTERPART_VAR="COUNTERPART_$ORIGIN"
    COUNTERPART="${!COUNTERPART_VAR}"
    # Randomly select asset
    RANDOM_INDEX=$((RANDOM % ${#ASSET_NAMES[@]}))
    ASSET="${ASSET_NAMES[$RANDOM_INDEX]}"
    AMOUNT="${ASSET_AMOUNTS[$RANDOM_INDEX]}"
    DECIMALS="${ASSET_DECIMALS[$RANDOM_INDEX]}"
    # Approve ERC20 token for the selected asset on the origin chain
    TOKEN_ADDR_VAR="${ASSET}_$ORIGIN"
    TOKEN_ADDR="${!TOKEN_ADDR_VAR}"
    if [[ -z "$TOKEN_ADDR" ]]; then
        echo "❌ Error: Token address for $ASSET on $ORIGIN is not set" >&2
        continue
    fi
    echo "✅ Approving $ASSET ($TOKEN_ADDR) for $AMOUNT on $ORIGIN..."
    cast send "$TOKEN_ADDR" "approve(address,uint256)" "$PROXY" "$AMOUNT" \
        --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --gas-limit 100000 2>/dev/null || {
        echo "⚠️ Approval for $ASSET on $ORIGIN failed (may already be approved or insufficient balance)" >&2
    }
    # Try transaction with up to 3 nonce attempts
    nonce_attempts=0
    max_nonce_attempts=3
    while [[ $nonce_attempts -lt $max_nonce_attempts ]]; do
        # Get random nonce
        NONCE=$(get_valid_nonce)
        if [[ $? -ne 0 ]]; then
            echo "❌ Skipping TX #$i due to nonce query failure" >&2
            break
        fi
        echo "📜 Using nonce: $NONCE on $ORIGIN (attempt $((nonce_attempts + 1))/$max_nonce_attempts)"
        # Encode order
        ORDER_DATA=$(encode_order_data "$ASSET" "$AMOUNT" "$DECIMALS" "$LOCAL_DOMAIN" "$DEST_DOMAIN" "$COUNTERPART" "$NONCE")
        if [[ $? -ne 0 ]]; then
            echo "❌ Skipping TX #$i due to order encoding failure" >&2
            break
        fi
        # Construct the STRUCT tuple as a string
        STRUCT="($FILL_DEADLINE,$ORDER_DATA_TYPE,$ORDER_DATA)"
        echo "🔍 Struct: $STRUCT" >&2
        echo ""
        echo "📦 TX #$i/$NUM_TXS | Direction: $ORIGIN -> $DEST | Asset: $ASSET | Amount: $AMOUNT | Nonce: $NONCE"
        # ERC20 transaction (USDC or WETH)
        TX_RESULT=$(cast send "$PROXY" "open((uint32,bytes32,bytes))" "$STRUCT" \
            --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --gas-limit 500000 2>&1)
        if [[ $? -eq 0 ]]; then
            echo "✅ TX #$i submitted!"
            break
        else
            echo "❌ TX #$i failed: $TX_RESULT" >&2
            nonce_attempts=$((nonce_attempts + 1))
            if [[ $nonce_attempts -eq $max_nonce_attempts ]]; then
                echo "❌ Skipping TX #$i after $max_nonce_attempts failed attempts" >&2
                break
            fi
            echo "⚠️ Retrying with new nonce..." >&2
        fi
    done
    # Wait interval (skip for last tx)
    if [[ $i -lt $NUM_TXS && $INTERVAL -gt 0 ]]; then
        echo "⏳ Waiting $INTERVAL seconds..."
        sleep "$INTERVAL"
    fi
done
echo ""
echo "🎉 Completed $NUM_TXS transactions!"