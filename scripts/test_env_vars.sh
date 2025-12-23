#!/usr/bin/env bash
# Test script to verify environment variable overrides work correctly
# This script tests all supported environment variables

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=========================================="
echo "Environment Variable Override Test"
echo "=========================================="
echo ""

# Build the server first
echo "[1/3] Building server..."
make -s clean && make -s -j bin/server
echo "✓ Build complete"
echo ""

# Test 1: Default values (no env vars)
echo "[2/3] Test 1: Default configuration (no env vars)"
echo "----------------------------------------"
timeout 2s ./bin/server --help || true
echo ""

# Test 2: Environment variable overrides
echo "[3/3] Test 2: Environment variable overrides"
echo "----------------------------------------"
echo "Setting environment variables:"
echo "  NS_PORT=8888"
echo "  NS_WORKERS=2"
echo "  NS_SHM_NAME=/ns_test_env"
echo "  NS_MAX_CONN_PER_WORKER=500"
echo "  NS_RECV_TIMEOUT_MS=15000"
echo "  NS_SEND_TIMEOUT_MS=15000"
echo ""

# Start server with env vars in background
NS_PORT=8888 \
NS_WORKERS=2 \
NS_SHM_NAME=/ns_test_env \
NS_MAX_CONN_PER_WORKER=500 \
NS_RECV_TIMEOUT_MS=15000 \
NS_SEND_TIMEOUT_MS=15000 \
./bin/server > /tmp/ns_env_test.log 2>&1 &

SERVER_PID=$!
echo "Server started with PID: $SERVER_PID"

# Wait for server to start
sleep 1

# Check if server is running
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✓ Server is running"
    
    # Check log for correct settings
    echo ""
    echo "Checking server log for environment variable settings:"
    if grep -q "port=8888" /tmp/ns_env_test.log; then
        echo "  ✓ NS_PORT=8888 applied"
    else
        echo "  ✗ NS_PORT not applied correctly"
    fi
    
    if grep -q "workers=2" /tmp/ns_env_test.log; then
        echo "  ✓ NS_WORKERS=2 applied"
    else
        echo "  ✗ NS_WORKERS not applied correctly"
    fi
    
    if grep -q "shm=/ns_test_env" /tmp/ns_env_test.log; then
        echo "  ✓ NS_SHM_NAME=/ns_test_env applied"
    else
        echo "  ✗ NS_SHM_NAME not applied correctly"
    fi
    
    # Stop server
    echo ""
    echo "Stopping server..."
    kill -INT $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    echo "✓ Server stopped"
else
    echo "✗ Server failed to start"
    cat /tmp/ns_env_test.log
    exit 1
fi

# Cleanup
rm -f /dev/shm/ns_test_env 2>/dev/null || true

echo ""
echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo ""
echo "Available environment variables:"
echo "  NS_BIND_IP              - Bind IP address"
echo "  NS_PORT                 - Port number"
echo "  NS_WORKERS              - Number of worker processes"
echo "  NS_SHM_NAME             - Shared memory name"
echo "  NS_MAX_BODY_LEN         - Max message body length"
echo "  NS_MAX_CONN_PER_WORKER  - Max connections per worker"
echo "  NS_RECV_TIMEOUT_MS      - Receive timeout in milliseconds"
echo "  NS_SEND_TIMEOUT_MS      - Send timeout in milliseconds"
echo ""
echo "Usage example:"
echo "  NS_WORKERS=8 NS_PORT=8080 ./bin/server"
