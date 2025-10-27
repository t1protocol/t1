#!/bin/bash

# Suppress Foundry nightly warning
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# source env
if [[ -f ".env" ]]; then
    source .env
fi

forge script ./script/test/7683/loadtesting/loadtest.s.sol:LoadTest --rpc-url $ARBITRUM_RPC --broadcast --private-key $ALICE_PRIVATE_KEY --sig "run(string)" "arb-to-base"
forge script ./script/test/7683/loadtesting/loadtest.s.sol:LoadTest --rpc-url $BASE_RPC --broadcast --private-key $ALICE_PRIVATE_KEY --sig "run(string)" "base-to-arb"