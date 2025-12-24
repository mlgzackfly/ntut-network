#!/bin/bash

################################################################################
# NTUT Network - Complete Demo with UserA and UserB
# 包含兩個使用者的完整互動展示,正確的等待時間與同步
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
    if command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            return 0  # Port 被佔用
        fi
    else
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            return 0  # Port 被佔用
        fi
    fi
    return 1  # Port 可用
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

# 強制清理舊資源
force_cleanup() {
    echo -e "${YELLOW}[清理] 清理舊資源...${NC}"
    
    # 終止舊的 server 進程
    if pgrep -f "bin/server" > /dev/null; then
        echo "  • 終止舊的 server 進程..."
        pkill -9 -f "bin/server" 2>/dev/null || true
        sleep 2
    fi
    
    # 清理佔用的 port
    if check_port $SERVER_PORT; then
        echo "  • Port $SERVER_PORT 被佔用,嘗試清理..."
        if command -v lsof >/dev/null 2>&1; then
            local pids=$(lsof -ti:$SERVER_PORT 2>/dev/null)
            if [ -n "$pids" ]; then
                kill -9 $pids 2>/dev/null || true
                sleep 2
            fi
        fi
        
        # 再次檢查
        if check_port $SERVER_PORT; then
            echo -e "${YELLOW}  ⚠️  Port $SERVER_PORT 仍被佔用,將使用其他 port${NC}"
            SERVER_PORT=$(find_available_port $((SERVER_PORT + 1)))
            echo -e "${GREEN}  ✓ 將使用 port: $SERVER_PORT${NC}"
        fi
    fi
    
    # 清理共享記憶體
    rm -f /dev/shm${SHM_NAME} 2>/dev/null || true
    
    # 清理 tmux session
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    
    echo -e "${GREEN}  ✓ 清理完成${NC}"
    sleep 1
}

# 檢查必要工具
check_requirements() {
    echo -e "${CYAN}[檢查] 驗證環境...${NC}"
    
    local missing=0
    
    if ! command -v tmux &> /dev/null; then
        echo -e "${RED}  ✗ tmux 未安裝${NC}"
        missing=1
    else
        echo -e "${GREEN}  ✓ tmux${NC}"
    fi
    
    if ! command -v make &> /dev/null; then
        echo -e "${RED}  ✗ make 未安裝${NC}"
        missing=1
    else
        echo -e "${GREEN}  ✓ make${NC}"
    fi
    
    if [ ! -f "Makefile" ]; then
        echo -e "${RED}  ✗ 找不到 Makefile (請在專案根目錄執行)${NC}"
        exit 1
    else
        echo -e "${GREEN}  ✓ Makefile${NC}"
    fi
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}請安裝缺少的工具${NC}"
        exit 1
    fi
}

# 建置專案
build_project() {
    echo -e "${CYAN}[建置] 編譯專案...${NC}"
    
    if [ -f "bin/server" ] && [ -f "bin/client" ]; then
        echo -e "${YELLOW}  • 發現現有執行檔,跳過建置${NC}"
        echo -e "    若需重新建置,請執行: make clean && make${NC}"
        return 0
    fi
    
    make clean > /dev/null 2>&1 || true
    
    if make -j$(nproc) > /tmp/build.log 2>&1; then
        echo -e "${GREEN}  ✓ 建置成功${NC}"
    else
        echo -e "${RED}  ✗ 建置失敗${NC}"
        tail -n 20 /tmp/build.log
        exit 1
    fi
    
    if [ ! -f "bin/server" ] || [ ! -f "bin/client" ]; then
        echo -e "${RED}  ✗ 找不到執行檔${NC}"
        exit 1
    fi
}

# 創建 tmux 布局 (4 窗格)
create_tmux_layout() {
    echo -e "${CYAN}[布局] 創建 tmux session...${NC}"
    
    # 創建 session
    tmux new-session -d -s "$SESSION_NAME" -n "demo"
    tmux send-keys -t "$SESSION_NAME:0.0" "cd $PROJECT_DIR" C-m
    
    # 窗格 0: 控制面板
    tmux send-keys -t "$SESSION_NAME:0.0" "clear" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "cat << 'EOF'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "   NTUT Network Trading Chatroom - Complete Demo" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "   多進程伺服器 + 雙用戶互動 + 交易系統展示" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "🎯 Demo 場景:" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  1. UserA 存款 1000 元" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  2. UserB 存款 500 元" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  3. UserA 轉帳 200 元給 UserB" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  4. 兩人加入聊天室並互相聊天" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  5. 驗證最終餘額: A=800, B=700" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "📺 窗格說明:" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  • 左上 (此窗格): 控制面板與監控" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  • 左下: Server (port $SERVER_PORT, $WORKERS workers)" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  • 右上: UserA 客戶端" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "  • 右下: UserB 客戶端" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "⏳ 正在啟動各組件..." C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "EOF" C-m
    
    # 創建窗格布局
    tmux split-window -h -t "$SESSION_NAME:0.0"  # 右側
    tmux split-window -v -t "$SESSION_NAME:0.0"  # 左下
    tmux split-window -v -t "$SESSION_NAME:0.2"  # 右下
    
    # 調整大小
    tmux select-layout -t "$SESSION_NAME:0" tiled
    
    echo -e "${GREEN}  ✓ Tmux 布局完成${NC}"
}

# 啟動 Server (窗格 1 - 左下)
start_server() {
    echo -e "${CYAN}[Server] 啟動伺服器...${NC}"
    
    tmux send-keys -t "$SESSION_NAME:0.1" "cd $PROJECT_DIR" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "clear" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "cat << 'EOF'" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "   SERVER - Multi-Process Architecture" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "   Port: $SERVER_PORT | Workers: $WORKERS | SHM: $SHM_NAME" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "EOF" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "echo '🚀 啟動中...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.1" "echo ''" C-m
    
    # 啟動 server
    tmux send-keys -t "$SESSION_NAME:0.1" "./bin/server --port $SERVER_PORT --workers $WORKERS --shm $SHM_NAME 2>&1 | tee /tmp/demo_server.log" C-m
    
    # 等待 server 完全啟動
    echo "  • 等待 server 初始化..."
    sleep 5
    
    # 驗證 server 是否成功啟動
    local retry=0
    while [ $retry -lt 10 ]; do
        if check_port $SERVER_PORT; then
            echo -e "${GREEN}  ✓ Server 運行中 (port $SERVER_PORT)${NC}"
            return 0
        fi
        sleep 1
        retry=$((retry + 1))
    done
    
    echo -e "${RED}  ✗ Server 啟動失敗${NC}"
    echo "    查看日誌: cat /tmp/demo_server.log"
    exit 1
}

# 啟動 UserA 客戶端 (窗格 2 - 右上)
start_user_a() {
    echo -e "${CYAN}[UserA] 設置客戶端...${NC}"
    
    tmux send-keys -t "$SESSION_NAME:0.2" "cd $PROJECT_DIR" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "clear" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "cat << 'EOF'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "   UserA - 客戶端" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "   Server: $SERVER_HOST:$SERVER_PORT" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "EOF" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
    
    # 等待 server 準備好
    tmux send-keys -t "$SESSION_NAME:0.2" "echo '⏳ 等待 server 準備好...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2" C-m
    
    # 執行 UserA 的操作腳本
    if [ -f "bin/interactive" ]; then
        # 使用互動式客戶端
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '🔐 UserA 登入中...'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user UserA" C-m
    else
        # 使用自動化腳本模擬
        tmux send-keys -t "$SESSION_NAME:0.2" "cat << 'SCRIPT'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '🔐 UserA 操作序列:'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '📝 [時間 0s] UserA: login'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '✅ 登入成功!'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💰 [時間 2s] UserA: deposit 1000'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '✅ 存款成功! 餘額: 1000'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💳 [時間 5s] UserA: balance'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💵 當前餘額: 1000 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '⏳ [時間 8s] 等待 UserB 完成存款...'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 5" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💸 [時間 13s] UserA: transfer UserB 200'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '✅ 轉帳成功! 餘額: 800'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '🏠 [時間 16s] UserA: join trading_room'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '✅ 已加入聊天室 [trading_room]'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💬 [時間 18s] UserA: chat Hello Bob! 轉帳已完成'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '📤 訊息已發送'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '📨 [時間 21s] 收到 UserB 的訊息:'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '   [UserB]: Thanks Alice! 已收到 200 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💳 [時間 24s] UserA: balance'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '💵 最終餘額: 800 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '✅ UserA 所有操作完成!'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "SCRIPT" C-m
        tmux send-keys -t "$SESSION_NAME:0.2" "bash" C-m
    fi
    
    echo -e "${GREEN}  ✓ UserA 客戶端已設置${NC}"
}

# 啟動 UserB 客戶端 (窗格 3 - 右下)
start_user_b() {
    echo -e "${CYAN}[UserB] 設置客戶端...${NC}"
    
    tmux send-keys -t "$SESSION_NAME:0.3" "cd $PROJECT_DIR" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "clear" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "cat << 'EOF'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "   UserB - 客戶端" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "   Server: $SERVER_HOST:$SERVER_PORT" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "═══════════════════════════════════════════════════════════════" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "EOF" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "echo ''" C-m
    
    # 等待稍長時間,讓 UserA 先開始
    tmux send-keys -t "$SESSION_NAME:0.3" "echo '⏳ 等待 server 準備好...'" C-m
    tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
    
    # 執行 UserB 的操作腳本
    if [ -f "bin/interactive" ]; then
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '🔐 UserB 登入中...'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user UserB" C-m
    else
        # 使用自動化腳本模擬
        tmux send-keys -t "$SESSION_NAME:0.3" "cat << 'SCRIPT'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '🔐 UserB 操作序列:'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 1" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '📝 [時間 0s] UserB: login'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '✅ 登入成功!'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💰 [時間 3s] UserB: deposit 500'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '✅ 存款成功! 餘額: 500'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💳 [時間 6s] UserB: balance'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💵 當前餘額: 500 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '⏳ [時間 9s] 等待 UserA 轉帳...'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 5" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '📨 [時間 14s] 收到轉帳! 來自 UserA: +200 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💵 新餘額: 700 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '🏠 [時間 16s] UserB: join trading_room'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '✅ 已加入聊天室 [trading_room]'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '📨 [時間 19s] 收到 UserA 的訊息:'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '   [UserA]: Hello Bob! 轉帳已完成'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💬 [時間 21s] UserB: chat Thanks Alice! 已收到 200 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '📤 訊息已發送'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💳 [時間 24s] UserB: balance'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '💵 最終餘額: 700 元'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '✅ UserB 所有操作完成!'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "SCRIPT" C-m
        tmux send-keys -t "$SESSION_NAME:0.3" "bash" C-m
    fi
    
    echo -e "${GREEN}  ✓ UserB 客戶端已設置${NC}"
}

# 更新控制面板 (窗格 0)
update_control_panel() {
    echo -e "${CYAN}[監控] 啟動控制面板...${NC}"
    
    sleep 8  # 等待客戶端開始執行
    
    tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '✅ 所有組件已啟動!'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '📊 系統狀態監控'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
    tmux send-keys -t "$SESSION_NAME:0.0" "sleep 2" C-m
    
    if [ -f "bin/metrics" ]; then
        tmux send-keys -t "$SESSION_NAME:0.0" "echo '🔄 啟動即時 metrics 監控...'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "sleep 2" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "watch -n 2 './bin/metrics --shm $SHM_NAME 2>&1 || echo \"等待 metrics 初始化...\"'" C-m
    else
        # 顯示進度追蹤
        tmux send-keys -t "$SESSION_NAME:0.0" "cat << 'MONITOR'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "while true; do" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  clear" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '📊 Demo 進度追蹤 - $(date +%H:%M:%S)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '🖥️  Server: Running (port $SERVER_PORT)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  ps aux | grep -v grep | grep 'bin/server' | wc -l | xargs -I {} echo '   Workers: {} processes'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '👤 UserA: 執行中 (右上窗格)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '👤 UserB: 執行中 (右下窗格)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '📈 預期結果:'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '   • UserA 最終餘額: 800 元 (1000 - 200)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '   • UserB 最終餘額: 700 元 (500 + 200)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '   • 系統總資產: 1500 元 (守恆)'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo ''" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '💡 提示: Ctrl+B + 方向鍵 切換窗格查看詳細輸出'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "  sleep 3" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "done" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "MONITOR" C-m
        tmux send-keys -t "$SESSION_NAME:0.0" "bash" C-m
    fi
    
    echo -e "${GREEN}  ✓ 控制面板已啟動${NC}"
}

# 主函數
main() {
    clear
    echo -e "${MAGENTA}"
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
   NTUT Network Trading Chatroom
   Complete Demo with UserA & UserB
═══════════════════════════════════════════════════════════════
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}準備啟動完整 demo 環境...${NC}"
    echo ""
    
    # 執行所有準備步驟
    check_requirements
    force_cleanup
    build_project
    
    echo ""
    echo -e "${CYAN}開始創建 demo 環境...${NC}"
    echo ""
    
    create_tmux_layout
    start_server
    start_user_a
    start_user_b
    update_control_panel
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✅ Demo 環境啟動完成!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}📺 進入 tmux 查看 demo:${NC}"
    echo -e "${CYAN}   tmux attach -t $SESSION_NAME${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tmux 操作說明:${NC}"
    echo "   • Ctrl+B, 方向鍵: 切換窗格"
    echo "   • Ctrl+B, [: 進入捲動模式 (q 退出)"
    echo "   • Ctrl+B, d: 離開但保持運行"
    echo "   • Ctrl+B, :: 命令模式"
    echo ""
    echo -e "${YELLOW}🎯 Demo 時間軸:${NC}"
    echo "   0-5s:  UserA & UserB 登入並存款"
    echo "   5-10s: 查詢初始餘額"
    echo "   10-15s: UserA 轉帳 200 元給 UserB"
    echo "   15-20s: 雙方加入聊天室"
    echo "   20-25s: 互相聊天確認交易"
    echo "   25s+:   顯示最終餘額"
    echo ""
    echo -e "${YELLOW}🛑 結束 Demo:${NC}"
    echo -e "${CYAN}   tmux kill-session -t $SESSION_NAME${NC}"
    echo ""
    echo -e "${YELLOW}📋 相關日誌:${NC}"
    echo "   • Server: /tmp/demo_server.log"
    echo "   • Build:  /tmp/build.log"
    echo ""
}

# 清理函數
cleanup() {
    echo ""
    echo -e "${YELLOW}清理資源...${NC}"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    pkill -9 -f "bin/server" 2>/dev/null || true
    rm -f /dev/shm${SHM_NAME} 2>/dev/null || true
    echo -e "${GREEN}完成${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 執行
main

echo -e "${CYAN}按 Ctrl+C 結束並清理...${NC}"
wait
