#!/usr/bin/env bash
# Quick demo script showing different environment variable configurations

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=========================================="
echo "Environment Variables Demo"
echo "=========================================="
echo ""

# Make sure server is built
if [ ! -f "./bin/server" ]; then
    echo "Building server..."
    make -s bin/server
fi

echo "This script demonstrates different server configurations using environment variables."
echo ""
echo "Press Ctrl+C to stop the server and try the next configuration."
echo ""

# Demo 1: Default configuration
echo "----------------------------------------"
echo "Demo 1: Default Configuration"
echo "----------------------------------------"
echo "Command: ./bin/server"
echo ""
read -p "Press Enter to start..."
./bin/server || true
echo ""

# Demo 2: High concurrency
echo "----------------------------------------"
echo "Demo 2: High Concurrency Configuration"
echo "----------------------------------------"
echo "Command: NS_WORKERS=16 NS_MAX_CONN_PER_WORKER=5000 ./bin/server"
echo ""
read -p "Press Enter to start..."
NS_WORKERS=16 NS_MAX_CONN_PER_WORKER=5000 ./bin/server || true
echo ""

# Demo 3: Custom port and shared memory
echo "----------------------------------------"
echo "Demo 3: Custom Port and Shared Memory"
echo "----------------------------------------"
echo "Command: NS_PORT=8080 NS_SHM_NAME=/ns_custom ./bin/server"
echo ""
read -p "Press Enter to start..."
NS_PORT=8080 NS_SHM_NAME=/ns_custom ./bin/server || true
echo ""

# Demo 4: Low latency
echo "----------------------------------------"
echo "Demo 4: Low Latency Configuration"
echo "----------------------------------------"
echo "Command: NS_RECV_TIMEOUT_MS=5000 NS_SEND_TIMEOUT_MS=5000 NS_WORKERS=8 ./bin/server"
echo ""
read -p "Press Enter to start..."
NS_RECV_TIMEOUT_MS=5000 NS_SEND_TIMEOUT_MS=5000 NS_WORKERS=8 ./bin/server || true
echo ""

echo "=========================================="
echo "Demo Complete"
echo "=========================================="
echo ""
echo "See docs/ENV_VARS.md for more examples and detailed documentation."
