#!/bin/bash

################################################################################
# NTUT Network - Fixed Demo Script with Port Conflict Handling
# 修正版 Demo 腳本,自動處理 port 衝突問題
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SESSION_NAME="ntut-network-demo"
SERVER_PORT=9000
SERVER_HOST="127.0.0.1"
WORKERS=4
SHM_NAME="/ns_trading_chat"
PROJECT_DIR="$(pwd)"

# 檢查 port 是否被佔用
check_port() {
  local port=$1
  if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
    return 0 # Port 被佔用
  else
    return 1 # Port 可用
  fi
}

# 找到可用的 port
find_available_port() {
  local start_port=$1
  local port=$start_port

  while [ $port -lt $((start_port + 100)) ]; do
    if ! check_port $port; then
      echo $port
      return 0
    fi
    port=$((port + 1))
  done

  echo -e "${RED}無法找到可用的 port${NC}" >&2
  return 1
}

# 強制清理舊的 server 進程
force_cleanup_servers() {
  echo -e "${YELLOW}檢查並清理舊的 server 進程...${NC}"

  # 方法 1: 通過程式名稱
  if pgrep -f "bin/server" >/dev/null; then
    echo "  發現殘留的 server 進程,正在終止..."
    pkill -9 -f "bin/server"
    sleep 2
  fi

  # 方法 2: 通過 port 佔用
  if check_port $SERVER_PORT; then
    echo "  Port $SERVER_PORT 仍被佔用,查找並終止佔用進程..."
    local pids=$(lsof -ti:$SERVER_PORT)
    if [ -n "$pids" ]; then
      echo "  終止 PIDs: $pids"
      kill -9 $pids 2>/dev/null || true
      sleep 2
    fi
  fi

  # 再次檢查
  if check_port $SERVER_PORT; then
    echo -e "${YELLOW}  ⚠️  Port $SERVER_PORT 仍然被佔用,將使用其他 port${NC}"
    SERVER_PORT=$(find_available_port $((SERVER_PORT + 1)))
    echo -e "${GREEN}  ✓ 將使用 port: $SERVER_PORT${NC}"
  else
    echo -e "${GREEN}  ✓ Port $SERVER_PORT 可用${NC}"
  fi
}

# 檢查必要工具
check_requirements() {
  echo -e "${CYAN}[INFO] 檢查必要工具...${NC}"

  if ! command -v tmux &>/dev/null; then
    echo -e "${RED}[ERROR] tmux 未安裝。請執行: sudo apt-get install tmux${NC}"
    exit 1
  fi

  if ! command -v lsof &>/dev/null; then
    echo -e "${YELLOW}[WARN] lsof 未安裝,將跳過 port 檢查${NC}"
  fi

  if ! command -v make &>/dev/null; then
    echo -e "${RED}[ERROR] make 未安裝${NC}"
    exit 1
  fi

  echo -e "${GREEN}[OK] 所有必要工具已就緒${NC}"
}

# 清理舊的 tmux session
cleanup_session() {
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo -e "${YELLOW}[INFO] 清理舊的 tmux session...${NC}"
    tmux kill-session -t "$SESSION_NAME"
    sleep 1
  fi
}

# 建置專案
build_project() {
  echo -e "${CYAN}[INFO] 建置專案...${NC}"
  if [ ! -f "Makefile" ]; then
    echo -e "${RED}[ERROR] 找不到 Makefile。請確認在專案根目錄執行此腳本${NC}"
    exit 1
  fi

  make clean >/dev/null 2>&1
  if ! make -j$(nproc) 2>&1 | tee /tmp/build_output.log; then
    echo -e "${RED}[ERROR] 建置失敗${NC}"
    tail -n 20 /tmp/build_output.log
    exit 1
  fi

  if [ ! -f "bin/server" ] || [ ! -f "bin/client" ]; then
    echo -e "${RED}[ERROR] 建置失敗,找不到可執行檔${NC}"
    exit 1
  fi

  echo -e "${GREEN}[OK] 專案建置完成${NC}"
}

# 清理共享記憶體
cleanup_shm() {
  echo -e "${CYAN}[INFO] 清理舊的共享記憶體...${NC}"
  if [ -e "/dev/shm${SHM_NAME}" ]; then
    rm -f "/dev/shm${SHM_NAME}"
  fi
}

# 創建 tmux session 和窗格布局
create_tmux_layout() {
  echo -e "${CYAN}[INFO] 創建 tmux session: ${SESSION_NAME}${NC}"

  tmux new-session -d -s "$SESSION_NAME" -n "demo"
  tmux send-keys -t "$SESSION_NAME:0.0" "cd $PROJECT_DIR" C-m

  # 顯示歡迎訊息
  tmux send-keys -t "$SESSION_NAME:0.0" "clear" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '   NTUT Network Trading Chatroom - Live Demo'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '   多進程伺服器 + 高並發客戶端 + 交易系統 + 聊天室'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '🔹 窗格布局說明:'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 左上 (當前): 控制面板'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 左下: Server (port $SERVER_PORT, $WORKERS workers)'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 右上: Client 1 - 互動式操作 (UserA)'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 右下: Client 2 - 壓力測試 (100+ 連線)'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '⏳ 正在設置 demo 環境...'" C-m

  # 垂直分割
  tmux split-window -h -t "$SESSION_NAME:0.0"
  tmux split-window -v -t "$SESSION_NAME:0.0"
  tmux split-window -v -t "$SESSION_NAME:0.2"

  # 調整窗格大小
  tmux select-layout -t "$SESSION_NAME:0" tiled

  sleep 2
}

# 啟動 Server (窗格 1)
start_server() {
  echo -e "${CYAN}[INFO] 啟動 Server...${NC}"

  tmux send-keys -t "$SESSION_NAME:0.1" "cd $PROJECT_DIR" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "clear" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "echo '   SERVER - Multi-Process Architecture'" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "echo '   Port: $SERVER_PORT | Workers: $WORKERS'" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "./bin/server --port $SERVER_PORT --workers $WORKERS --shm $SHM_NAME 2>&1 | tee /tmp/demo_server_output.log" C-m

  # 等待 server 啟動
  echo "  等待 server 啟動..."
  sleep 5

  # 驗證 server 是否成功啟動
  if check_port $SERVER_PORT; then
    echo -e "${GREEN}[OK] Server 已啟動 (Port: $SERVER_PORT, Workers: $WORKERS)${NC}"
  else
    echo -e "${RED}[ERROR] Server 啟動失敗,請檢查 tmux 窗格中的錯誤訊息${NC}"
    echo "提示: 執行 'tmux attach -t $SESSION_NAME' 查看詳細錯誤"
    exit 1
  fi
}

# 啟動互動式 Client (窗格 2)
start_interactive_client() {
  echo -e "${CYAN}[INFO] 設置互動式 Client (UserA)...${NC}"

  tmux send-keys -t "$SESSION_NAME:0.2" "cd $PROJECT_DIR" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "clear" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '   CLIENT 1 - Interactive Mode (UserA)'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '   Server: $SERVER_HOST:$SERVER_PORT'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '💡 Trading 操作範例:'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  1. login'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  2. deposit 1000        # 存款 1000 元'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  3. balance             # 查詢餘額'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  4. withdraw 300        # 提款 300 元'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  5. transfer Bob 200    # 轉帳給 Bob'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo '  6. balance             # 查詢最終餘額'" C-m
  tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m

  if [ -f "bin/interactive" ]; then
    tmux send-keys -t "$SESSION_NAME:0.2" "echo '🚀 啟動互動式客戶端...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user UserA" C-m
  else
    tmux send-keys -t "$SESSION_NAME:0.2" "echo '⚠️  找不到 bin/interactive'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "echo '可使用基本客戶端測試:'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "echo '  ./bin/client --host $SERVER_HOST --port $SERVER_PORT --connections 1 --threads 1 --duration 10 --mix trade'" C-m
  fi

  sleep 2
}

# 啟動壓力測試 Client (窗格 3)
start_stress_client() {
  echo -e "${CYAN}[INFO] 設置壓力測試 Client...${NC}"

  tmux send-keys -t "$SESSION_NAME:0.3" "cd $PROJECT_DIR" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "clear" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "echo '═══════════════════════════════════════════════════════════════'" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "echo '   CLIENT 2 - Stress Test Mode'" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "echo '   配置: 100 連線 | 16 執行緒 | Trading 工作負載'" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "echo '   Server: $SERVER_HOST:$SERVER_PORT'" C-m
  tmux send-keys -t "$SESSION_NAME:0.3" "echo '═══════════════════════════════════════════════════════════════'" C-m
  sleep 2

  if [ ! -f "bin/client" ]; then
    tmux send-keys -t "$SESSION_NAME:0.3" "echo '❌ 找不到 bin/client'" C-m
  else
    tmux send-keys -t "$SESSION_NAME:0.3" "echo '⏳ 等待 5 秒後開始壓力測試...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "sleep 5" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "echo '🔥 啟動壓力測試 (30 秒)...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "./bin/client --host $SERVER_HOST --port $SERVER_PORT --connections 100 --threads 16 --duration 30 --mix trade --out /tmp/demo_stress_test.csv" C-m
  fi

  sleep 2
}

# 更新控制面板
update_control_panel() {
  sleep 5

  tmux send-keys -t "$SESSION_NAME:0.0" "" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '✅ Demo 環境設置完成!'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '📊 連線資訊:'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • Server: $SERVER_HOST:$SERVER_PORT'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • Workers: $WORKERS'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • Shared Memory: $SHM_NAME'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '🎯 Trading 功能展示:'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  ✓ DEPOSIT  - 存款'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  ✓ WITHDRAW - 提款'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  ✓ TRANSFER - 轉帳 (Deadlock-free)'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '  ✓ BALANCE  - 查詢餘額'" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "echo '📈 即時監控:'" C-m

  if [ -f "bin/metrics" ]; then
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  啟動 metrics 監控...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "sleep 2" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "watch -n 2 './bin/metrics --shm $SHM_NAME 2>/dev/null || echo Waiting for metrics...'" C-m
  else
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  手動查看: ./bin/metrics --shm $SHM_NAME'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '💡 操作提示:'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • Ctrl+B + 方向鍵: 切換窗格'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 在右上窗格執行 trading 操作'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 觀察左下 server 的處理日誌'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '  • 右下窗格顯示壓力測試結果'" C-m
  fi
}

# 主函數
main() {
  echo -e "${MAGENTA}"
  echo "═══════════════════════════════════════════════════════════════"
  echo "   NTUT Network Trading Chatroom - Fixed Demo Script"
  echo "   自動處理 Port 衝突與清理問題"
  echo "═══════════════════════════════════════════════════════════════"
  echo -e "${NC}"

  check_requirements
  cleanup_session
  force_cleanup_servers
  cleanup_shm
  build_project

  create_tmux_layout
  start_server
  start_interactive_client
  start_stress_client
  update_control_panel

  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}   ✅ Demo 環境已成功啟動!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${CYAN}📺 執行以下指令進入 tmux:${NC}"
  echo -e "${YELLOW}   tmux attach -t $SESSION_NAME${NC}"
  echo ""
  echo -e "${CYAN}💡 Tmux 操作:${NC}"
  echo "   • Ctrl+B, 方向鍵: 切換窗格"
  echo "   • Ctrl+B, [: 捲動模式 (q 退出)"
  echo "   • Ctrl+B, d: 離開 (session 保持運行)"
  echo ""
  echo -e "${CYAN}🛑 結束 Demo:${NC}"
  echo -e "${YELLOW}   tmux kill-session -t $SESSION_NAME${NC}"
  echo ""
  echo -e "${CYAN}📋 Server 資訊:${NC}"
  echo "   Port: $SERVER_PORT"
  echo "   Workers: $WORKERS"
  echo "   Log: /tmp/demo_server_output.log"
  echo ""
}

cleanup() {
  echo ""
  echo -e "${YELLOW}[INFO] 接收到中斷信號,清理資源...${NC}"
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  pkill -9 -f "bin/server" 2>/dev/null || true
  cleanup_shm
  echo -e "${GREEN}[OK] 清理完成${NC}"
  exit 0
}

trap cleanup SIGINT SIGTERM

main

echo -e "${CYAN}按 Ctrl+C 結束並清理...${NC}"
wait
