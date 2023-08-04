#!/usr/bin/env bash

set -e

PORT=8545
HOST="0.0.0.0"
SLEEP_DURATION=0.1

# Start the Anvil server in auto-impersonate mode.
anvil --auto-impersonate --host "$HOST" --rpc-url "$MAINNET_RPC_URL" &
ANVIL_PID=$!

# Wait until Anvil is ready
while ! nc -z localhost "$PORT"; do sleep "$SLEEP_DURATION"; done

# Deploy contracts, forking from the provided RPC URL
forge script script/Deploy.s.sol --rpc-url "http://localhost:$PORT" --unlocked --broadcast --sender "$DEPLOYER"

# Wait for Anvil
wait $ANVIL_PID
