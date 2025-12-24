#!/bin/bash

################################################################################
# NTUT Network - Cross-Worker Broadcast Demo
# 展示跨 Worker 進程的聊天訊息廣播功能
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SESSION_NAME="cross-worker-demo"
SERVER_PORT=9000
SERVER_HOST="127.0.0.1"
WORKERS=4
SHM_NAME="/ns_trading_chat"

# 清理函數
cleanup() {
    echo ""
    echo -e "${YELLOW}清理資源...${NC}"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    pkill -f "bin/server" 2>/dev/null || true
    rm -f /dev/shm${SHM_NAME} 2>/dev/null || true
    echo -e "${GREEN}清理完成${NC}"
}

trap cleanup EXIT

echo -e "${MAGENTA}"
echo "═══════════════════════════════════════════════════════════════"
echo "   Cross-Worker Broadcast Demo"
echo "   證明不同 Worker 進程間的聊天訊息廣播"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo ""

# 1. 清理舊環境
echo -e "${CYAN}[1/5] 清理舊環境...${NC}"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
rm -f /dev/shm${SHM_NAME}
sleep 1

# 2. 啟動 Server
echo -e "${CYAN}[2/5] 啟動 Server ($WORKERS workers)...${NC}"
if [ ! -f "bin/server" ]; then
    echo -e "${RED}錯誤: 找不到 bin/server,請先執行 make${NC}"
    exit 1
fi

./bin/server --port $SERVER_PORT --workers $WORKERS --shm $SHM_NAME > /tmp/cross_worker_server.log 2>&1 &
SERVER_PID=$!

echo "  Server PID: $SERVER_PID"
echo "  等待 server 初始化..."
sleep 3

# 檢查 server 是否正常運行
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Server 啟動失敗,請檢查日誌: /tmp/cross_worker_server.log${NC}"
    cat /tmp/cross_worker_server.log
    exit 1
fi

echo -e "${GREEN}  Server 啟動成功!${NC}"
echo ""

# 3. 創建 tmux session
echo -e "${CYAN}[3/5] 創建 tmux session...${NC}"
tmux new-session -d -s "$SESSION_NAME" -n "demo"

# 上半部: Server 日誌
tmux send-keys -t "$SESSION_NAME:0.0" "tail -f /tmp/cross_worker_server.log" C-m

# 水平分割: Client 1
tmux split-window -h -t "$SESSION_NAME:0.0"

# 再次水平分割: Client 2
tmux split-window -h -t "$SESSION_NAME:0.1"

# 調整窗格大小
tmux select-layout -t "$SESSION_NAME:0" even-horizontal

echo -e "${GREEN}  Tmux session 創建完成${NC}"
echo ""

# 4. 設置客戶端窗格
echo -e "${CYAN}[4/5] 設置客戶端窗格...${NC}"

# Client 1 窗格
tmux send-keys -t "$SESSION_NAME:0.1" "clear" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '═══════════════════════════════════════'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '  Client 1 - User: Alice'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '═══════════════════════════════════════'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo ''" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '🔸 此客戶端將連接到某個 Worker A'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '🔸 請在此窗格手動執行:'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '   ./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user Alice'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo ''" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '然後執行:'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '  1) login'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '  2) join trading_room'" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '  3) chat Hello from Alice!'" C-m

# Client 2 窗格
tmux send-keys -t "$SESSION_NAME:0.2" "clear" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '═══════════════════════════════════════'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '  Client 2 - User: Bob'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '═══════════════════════════════════════'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '🔸 此客戶端可能連接到不同 Worker B'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '🔸 請在此窗格手動執行:'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '   ./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user Bob'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '然後執行:'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '  1) login'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '  2) join trading_room'" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '  3) chat Hi Alice, this is Bob!'" C-m

sleep 2
echo -e "${GREEN}  客戶端窗格設置完成${NC}"
echo ""

# 5. 顯示說明
echo -e "${CYAN}[5/5] Demo 環境已就緒!${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✅ Cross-Worker Broadcast Demo 環境啟動成功!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}📺 請執行以下指令進入 tmux session:${NC}"
echo -e "${CYAN}   tmux attach -t $SESSION_NAME${NC}"
echo ""
echo -e "${YELLOW}📝 測試步驟:${NC}"
echo "   1. 進入 tmux (上面的指令)"
echo "   2. 使用 Ctrl+B 然後按方向鍵切換到 Client 1 窗格 (中間)"
echo "   3. 執行提示的指令啟動 interactive client (Alice)"
echo "   4. 使用 Ctrl+B 然後按方向鍵切換到 Client 2 窗格 (右側)"
echo "   5. 執行提示的指令啟動 interactive client (Bob)"
echo "   6. 在兩個 client 窗格中交替發送訊息"
echo "   7. 觀察左側 Server 日誌,確認訊息經過不同 Worker"
echo "   8. 驗證兩個 client 都能收到彼此的訊息 (cross-worker broadcast)"
echo ""
echo -e "${YELLOW}💡 驗證要點:${NC}"
echo "   • Server 日誌會顯示每條訊息由哪個 Worker PID 處理"
echo "   • 如果 Alice 和 Bob 連到不同 Worker,仍能互相收訊息"
echo "   • 這證明了共享記憶體的 room broadcast 機制正常運作"
echo ""
echo -e "${YELLOW}📸 截圖建議:${NC}"
echo "   • 截取整個 tmux 畫面,顯示三個窗格"
echo "   • 確保能看到:"
echo "     1) Server 日誌中的不同 Worker PID"
echo "     2) Client 1 發送的訊息"
echo "     3) Client 2 收到的訊息 (或反之)"
echo ""
echo -e "${YELLOW}🛑 結束 Demo:${NC}"
echo -e "${CYAN}   tmux kill-session -t $SESSION_NAME${NC}"
echo "   或在任一窗格按 Ctrl+D 退出,然後在此終端按 Ctrl+C"
echo ""
echo -e "${BLUE}按 Ctrl+C 清理並結束...${NC}"

# 等待用戶操作
wait $SERVER_PID
