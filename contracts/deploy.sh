#!/usr/bin/env bash

# Exit immediately if any command fails and treat unset variables as errors
set -euo pipefail

# Function to load environment variables from .env
reload_env() {
  set -o allexport
  source .env || true
  set +o allexport
}


# Initial environment load
reload_env

# Function to determine RPC URL from the script name, dirty
get_rpc_url() {
  local script_name=$1

  if [[ $script_name == *"L1"* ]]; then
    echo "$T1_L1_RPC"
  elif [[ $script_name == *"L2"* ]]; then
    echo "$T1_L2_RPC"
  else
    echo "ERROR: Could not determine RPC URL for script: $script_name" >&2
    exit 1
  fi
}

# Function to execute a script with the correct RPC URL
run_script() {
  local script_path=$1
  local contract_name=$2
  local rpc_url

  rpc_url=$(get_rpc_url "$contract_name")

  echo "=== Running $contract_name ==="
  forge script "$script_path:$contract_name" --rpc-url "$rpc_url" --broadcast

  # Wait for the .env file to be updated
  sleep 10
  #reload_env
}

# Deploy contracts
run_script script/deploy/DeployL1BridgeProxyPlaceholder.s.sol DeployL1BridgeProxyPlaceholder
run_script script/deploy/DeployL1T1Owner.s.sol DeployL1T1Owner
run_script script/deploy/DeployL2BridgeProxyPlaceholder.s.sol DeployL2BridgeProxyPlaceholder
run_script script/deploy/DeployL2T1Owner.s.sol DeployL2T1Owner
run_script script/deploy/DeployL2Weth.s.sol DeployL2Weth
run_script script/deploy/DeployL2BridgeContracts.s.sol DeployL2BridgeContracts
run_script script/deploy/DeployL1BridgeContracts.s.sol DeployL1BridgeContracts
run_script script/deploy/InitializeL1BridgeContracts.s.sol InitializeL1BridgeContracts
run_script script/deploy/InitializeL2BridgeContracts.s.sol InitializeL2BridgeContracts
run_script script/deploy/InitializeL1T1Owner.s.sol InitializeL1T1Owner
run_script script/deploy/InitializeL2T1Owner.s.sol InitializeL2T1Owner
