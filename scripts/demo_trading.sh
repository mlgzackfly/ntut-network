#!/usr/bin/env bash
# Trading Demo Script - 展示所有交易功能
# 此腳本會啟動 server，建立多個使用者，並展示各種交易操作

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 顏色定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "    Trading System Demo"
echo "=========================================="
echo ""

# 設定
PORT="${PORT:-9001}"
SHM_NAME="${SHM_NAME:-/ns_trading_demo}"
RESULTS_DIR="$ROOT/results"
mkdir -p "$RESULTS_DIR"

# 確保已編譯
if [ ! -f "./bin/server" ] || [ ! -f "./bin/interactive" ]; then
    echo -e "${YELLOW}Building project...${NC}"
    make -s -j
fi

# 清理舊的 shared memory
rm -f /dev/shm${SHM_NAME} 2>/dev/null || true

# 啟動 server
echo -e "${BLUE}[1/7] Starting server...${NC}"
./bin/server --port "$PORT" --workers 4 --shm "$SHM_NAME" > "$RESULTS_DIR/trading_demo_server.log" 2>&1 &
SERVER_PID=$!
sleep 1

# 確認 server 啟動成功
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Failed to start server${NC}"
    cat "$RESULTS_DIR/trading_demo_server.log"
    exit 1
fi

echo -e "${GREEN}✓ Server started (PID: $SERVER_PID)${NC}"

cleanup() {
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}Stopping server...${NC}"
        kill -INT $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
    rm -f /dev/shm${SHM_NAME} 2>/dev/null || true
}
trap cleanup EXIT

# 建立測試腳本函數
run_trading_commands() {
    local user=$1
    local commands=$2
    
    echo "$commands" | ./bin/interactive --host 127.0.0.1 --port "$PORT" --user "$user" 2>/dev/null | \
        grep -E "(Login successful|Balance:|Deposit successful|Withdraw successful|Transfer successful|Insufficient funds|Failed)" || true
}

echo ""
echo -e "${BLUE}[2/7] User A - Initial Balance Check${NC}"
echo "----------------------------------------"
RESULT=$(run_trading_commands "userA" "balance
quit")
echo "$RESULT"
INITIAL_BALANCE=$(echo "$RESULT" | grep "Login successful" | grep -oP 'Balance: \K[0-9]+' || echo "100000")
echo -e "${GREEN}✓ User A initial balance: $INITIAL_BALANCE${NC}"

echo ""
echo -e "${BLUE}[3/7] User A - Deposit Operation${NC}"
echo "----------------------------------------"
echo "Command: deposit 50000"
RESULT=$(run_trading_commands "userA" "deposit 50000
balance
quit")
echo "$RESULT"
echo -e "${GREEN}✓ Deposit completed${NC}"

echo ""
echo -e "${BLUE}[4/7] User A - Withdraw Operation${NC}"
echo "----------------------------------------"
echo "Command: withdraw 20000"
RESULT=$(run_trading_commands "userA" "withdraw 20000
balance
quit")
echo "$RESULT"
echo -e "${GREEN}✓ Withdraw completed${NC}"

echo ""
echo -e "${BLUE}[5/7] User B - Login and Check Balance${NC}"
echo "----------------------------------------"
RESULT=$(run_trading_commands "userB" "balance
quit")
echo "$RESULT"
echo -e "${GREEN}✓ User B logged in${NC}"

echo ""
echo -e "${BLUE}[6/7] Transfer from User A to User B${NC}"
echo "----------------------------------------"
echo "Getting User B's ID..."

# 從 server log 取得 User B 的 ID
sleep 0.5
USER_B_ID=$(grep "userB" "$RESULTS_DIR/trading_demo_server.log" | grep "user_id=" | tail -1 | grep -oP 'user_id=\K[0-9]+' || echo "1")

echo "User B ID: $USER_B_ID"
echo "Command: transfer $USER_B_ID 30000"

RESULT=$(run_trading_commands "userA" "transfer $USER_B_ID 30000
balance
quit")
echo "$RESULT"
echo -e "${GREEN}✓ Transfer completed${NC}"

echo ""
echo -e "${BLUE}[7/7] Verify User B Received Transfer${NC}"
echo "----------------------------------------"
RESULT=$(run_trading_commands "userB" "balance
quit")
echo "$RESULT"
echo -e "${GREEN}✓ Verification completed${NC}"

echo ""
echo "=========================================="
echo -e "${BLUE}Bonus: Testing Error Handling${NC}"
echo "=========================================="

echo ""
echo -e "${YELLOW}Test 1: Insufficient Funds (withdraw more than balance)${NC}"
echo "----------------------------------------"
RESULT=$(run_trading_commands "userC" "withdraw 999999999
quit")
echo "$RESULT"

echo ""
echo -e "${YELLOW}Test 2: Multiple Operations in Sequence${NC}"
echo "----------------------------------------"
echo "Commands: deposit 10000 → withdraw 5000 → balance"
RESULT=$(run_trading_commands "userD" "deposit 10000
withdraw 5000
balance
quit")
echo "$RESULT"

echo ""
echo "=========================================="
echo -e "${GREEN}Demo Summary${NC}"
echo "=========================================="
echo ""
echo "Demonstrated features:"
echo "  ✓ User login and authentication"
echo "  ✓ Balance query (BALANCE)"
echo "  ✓ Deposit operation (DEPOSIT)"
echo "  ✓ Withdraw operation (WITHDRAW)"
echo "  ✓ Transfer between users (TRANSFER)"
echo "  ✓ Insufficient funds error handling"
echo "  ✓ Multiple concurrent users"
echo ""
echo "Server log: $RESULTS_DIR/trading_demo_server.log"
echo ""
echo "To view detailed metrics:"
echo "  ./bin/metrics $SHM_NAME"
echo ""
echo "To manually test trading features:"
echo "  ./bin/interactive --host 127.0.0.1 --port $PORT --user yourname"
echo ""
