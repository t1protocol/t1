#!/bin/bash

# ---------------------------------------
# Usage
# ---------------------------------------
#  ./generate_wallets.sh <number_of_wallets> [-a]
#     - <number_of_wallets> is required
#     - use -a to auto-append to genesis.json
# ---------------------------------------

USAGE="Usage: $0 <number_of_wallets> [-a]"
AUTO_APPEND=false

# 1) Check if user provided at least one argument
if [ -z "$1" ]; then
  echo "$USAGE"
  exit 1
fi

# 2) First argument should be the number of wallets
N="$1"

# Check that N is a valid positive integer
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "Error: '$N' is not a valid number."
  echo "$USAGE"
  exit 1
fi

# 3) Check if the second argument is the -a flag
if [ "$2" == "-a" ]; then
  AUTO_APPEND=true
fi

OUTPUT_FILE="wallets.txt"
GENESIS_PATH="../../infrastructure/docker-compose/reth/network-configs/genesis.json"

# Clear previous output
> "$OUTPUT_FILE"

echo "Generating $N Ethereum wallets..."
echo ""

for i in $(seq 1 "$N"); do
  # Generate a random private key (32 bytes hex)
  PRIVATE_KEY=$(openssl rand -hex 32)

  # Generate Ethereum address from the private key using Foundry's `cast`
  ADDRESS=$(cast wallet address "$PRIVATE_KEY")

  if [ -z "$ADDRESS" ]; then
    echo "❌ Error generating address. Exiting..."
    exit 1
  fi

  # Print the wallet details to terminal
  echo "Address: $ADDRESS"
  echo "Private Key: $PRIVATE_KEY"
  echo ""

  # Save private key and address to file
  {
    echo "Address: $ADDRESS"
    echo "Private Key: $PRIVATE_KEY"
    echo ""
  } >> "$OUTPUT_FILE"
done

# ----------------------------------------
# Auto-append to genesis.json if -a is passed
# ----------------------------------------
if $AUTO_APPEND; then
  # Only proceed if the genesis.json exists
  if [ -f "$GENESIS_PATH" ]; then
    # Check that jq is installed
    if ! command -v jq &> /dev/null; then
      echo "⚠️ 'jq' not found. Please install 'jq' to automatically update genesis.json."
    else
      echo "Appending newly generated wallets into '$GENESIS_PATH'..."

      # Create a temporary JSON object with all newly generated addresses
      new_alloc=$(jq -n '{}')

      # Build a JSON object for the new wallets
      for i in $(seq 1 "$N"); do
        ADDRESS_LINE_NUM=$(( (i - 1) * 3 + 1 ))
        ADDRESS=$(sed -n "${ADDRESS_LINE_NUM}p" "$OUTPUT_FILE" | cut -d " " -f2)

        # Merge each address into our new_alloc JSON with default balance
        new_alloc=$(echo "$new_alloc" | jq --arg addr "$ADDRESS" '
          . + {($addr): {"balance": "1000000000000000000000000"}}
        ')
      done

      # Backup the existing genesis.json before modifying
      backup_file="../../infrastructure/docker-compose/reth/network-configs/genesis_backup_$(date +'%Y%m%d%H%M%S').json"
      cp "$GENESIS_PATH" "$backup_file"

      # -----------------------------------------------------
      # Instead of --argfile, create a temp file for new_alloc
      # -----------------------------------------------------
      tmp_file="$(mktemp)"
      echo "$new_alloc" > "$tmp_file"

      # Merge new addresses into .alloc in genesis.json
      updated_genesis=$(jq '.alloc += input' "$GENESIS_PATH" "$tmp_file")

      # Overwrite the updated genesis.json
      echo "$updated_genesis" > "$GENESIS_PATH"

      # Clean up temp file
      rm -f "$tmp_file"

      echo "✅ Successfully appended new wallets to: $GENESIS_PATH"
      echo "  (Backup of old genesis.json at: $backup_file )"
    fi
  else
    echo "⚠️  '$GENESIS_PATH' not found. Skipping auto-append."
  fi
fi
# ----------------------------------------

# Print ready-to-paste alloc lines for manual editing (optional)
echo "📜 Paste this into 'alloc' in a genesis.json if needed:"
echo "{"
echo '  "alloc": {'

for i in $(seq 1 "$N"); do
  ADDRESS_LINE_NUM=$(( (i - 1) * 3 + 1 ))
  ADDRESS=$(sed -n "${ADDRESS_LINE_NUM}p" "$OUTPUT_FILE" | cut -d " " -f2)

  echo "    \"$ADDRESS\": {"
  echo "      \"balance\": \"1000000000000000000000000\""
  if [ "$i" -ne "$N" ]; then
    echo "    },"
  else
    echo "    }"
  fi
done

echo "  }"
echo "}"

echo ""
echo "✅ $N wallets generated!"
echo "📄 Private keys saved in: $OUTPUT_FILE"

