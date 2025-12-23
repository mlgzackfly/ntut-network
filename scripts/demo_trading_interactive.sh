#!/usr/bin/env bash
# Interactive Trading Demo - 互動式交易展示
# 此腳本提供一個互動式介面，讓使用者可以手動執行交易操作

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 顏色定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        Trading System - Interactive Demo                    ║
║                                                              ║
║  This demo will guide you through all trading features      ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF

echo ""
echo -e "${BLUE}Available Trading Operations:${NC}"
echo "  1. BALANCE  - Check your account balance"
echo "  2. DEPOSIT  - Add money to your account"
echo "  3. WITHDRAW - Remove money from your account"
echo "  4. TRANSFER - Send money to another user"
echo ""

# 設定
PORT="${PORT:-9002}"
SHM_NAME="${SHM_NAME:-/ns_trading_interactive}"

# 確保已編譯
if [ ! -f "./bin/server" ] || [ ! -f "./bin/interactive" ]; then
    echo -e "${YELLOW}Building project...${NC}"
    make -s -j
fi

# 清理舊的 shared memory
rm -f /dev/shm${SHM_NAME} 2>/dev/null || true

# 啟動 server
echo -e "${BLUE}Starting server...${NC}"
./bin/server --port "$PORT" --workers 4 --shm "$SHM_NAME" > /tmp/trading_interactive_server.log 2>&1 &
SERVER_PID=$!
sleep 1

# 確認 server 啟動成功
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Failed to start server${NC}"
    cat /tmp/trading_interactive_server.log
    exit 1
fi

echo -e "${GREEN}✓ Server started successfully${NC}"
echo ""

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

# 提示使用者輸入名稱
echo -e "${CYAN}Please enter your username:${NC}"
read -p "> " USERNAME

if [ -z "$USERNAME" ]; then
    USERNAME="demo_user"
fi

echo ""
echo -e "${BLUE}Connecting as: $USERNAME${NC}"
echo ""
echo -e "${YELLOW}Quick Start Guide:${NC}"
echo "  • Type 'balance' to check your balance"
echo "  • Type 'deposit 1000' to add 1000 to your account"
echo "  • Type 'withdraw 500' to remove 500 from your account"
echo "  • Type 'transfer <user_id> <amount>' to send money"
echo "  • Type 'quit' to exit"
echo ""
echo -e "${CYAN}Tip: Open another terminal and run this script again"
echo "     with a different username to test transfers!${NC}"
echo ""
echo "Press Enter to start..."
read

# 啟動 interactive client
./bin/interactive --host 127.0.0.1 --port "$PORT" --user "$USERNAME"

echo ""
echo -e "${GREEN}Thank you for using the Trading System Demo!${NC}"
