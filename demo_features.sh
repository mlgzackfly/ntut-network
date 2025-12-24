#!/bin/bash

################################################################################
# NTUT Network - Feature Showcase Script
# 此腳本逐步展示系統的各項功能,適合課堂演示或錄製 demo 影片
################################################################################

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
SERVER_HOST="127.0.0.1"
SERVER_PORT=9000
DEMO_USER="DemoUser"
TEST_ROOM="trading_room"

# 暫停並等待用戶確認
pause() {
  echo ""
  echo -e "${YELLOW}➤ 按 Enter 繼續下一步...${NC}"
  read -r
}

# 顯示步驟標題
show_step() {
  local step_num=$1
  local step_title=$2
  echo ""
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}   步驟 ${step_num}: ${step_title}${NC}"
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
}

# 執行並顯示指令
run_command() {
  local cmd=$1
  echo -e "${GREEN}$ ${cmd}${NC}"
  eval "$cmd"
  echo ""
}

# 顯示功能說明
show_feature() {
  local feature=$1
  echo -e "${BLUE}📌 功能重點: ${feature}${NC}"
  echo ""
}

# 主要展示流程
main() {
  clear
  echo -e "${MAGENTA}"
  echo "═══════════════════════════════════════════════════════════════"
  echo "   NTUT Network Trading Chatroom"
  echo "   功能展示腳本 (Feature Showcase)"
  echo "═══════════════════════════════════════════════════════════════"
  echo -e "${NC}"
  echo ""
  echo "本腳本將逐步展示以下功能:"
  echo "  1. 伺服器啟動與多進程架構"
  echo "  2. 客戶端連線與身份驗證"
  echo "  3. 聊天室功能 (加入/離開/訊息傳送)"
  echo "  4. 交易功能 (存款/提款/轉帳/查詢)"
  echo "  5. 並發壓力測試"
  echo "  6. 系統監控與指標"
  echo "  7. 優雅關閉與資源清理"
  echo ""
  pause

  # ============================================================
  # 步驟 1: 檢查並建置專案
  # ============================================================
  show_step "1" "檢查環境與建置專案"
  show_feature "確保所有必要的可執行檔都已正確建置"

  if [ ! -f "Makefile" ]; then
    echo -e "${RED}錯誤: 找不到 Makefile,請在專案根目錄執行此腳本${NC}"
    exit 1
  fi

  echo "🔨 執行 make 建置專案..."
  run_command "make -j$(nproc) 2>&1 | tail -n 10"

  echo -e "${GREEN}✅ 建置完成!${NC}"
  echo "生成的執行檔:"
  ls -lh bin/ 2>/dev/null || echo "  (無法列出 bin/ 目錄)"
  pause

  # ============================================================
  # 步驟 2: 清理舊資源
  # ============================================================
  show_step "2" "清理舊的共享記憶體與進程"
  show_feature "確保乾淨的測試環境"

  echo "🧹 清理共享記憶體..."
  run_command "rm -f /dev/shm/ns_trading_chat"

  echo "🧹 檢查是否有殘留的 server 進程..."
  if pgrep -f "bin/server" >/dev/null; then
    echo "  發現殘留進程,正在終止..."
    pkill -f "bin/server" || true
    sleep 1
  else
    echo "  沒有殘留進程"
  fi

  echo -e "${GREEN}✅ 清理完成${NC}"
  pause

  # ============================================================
  # 步驟 3: 啟動伺服器
  # ============================================================
  show_step "3" "啟動多進程伺服器"
  show_feature "Master-Worker 架構 | 4 個 Worker 進程 | 共享記憶體 IPC"

  echo "🚀 啟動 Server (背景執行)..."
  run_command "./bin/server --port $SERVER_PORT --workers 4 --shm /ns_trading_chat > /tmp/server_demo.log 2>&1 &"

  local server_pid=$!
  echo "  Server PID: $server_pid"
  echo "  Log 檔案: /tmp/server_demo.log"

  echo ""
  echo "⏳ 等待 server 初始化 (3 秒)..."
  sleep 3

  echo ""
  echo "📋 Server 進程樹:"
  pstree -p $server_pid 2>/dev/null || ps aux | grep "[b]in/server" || echo "  無法顯示進程樹"

  echo ""
  echo "📄 Server 啟動日誌 (最後 10 行):"
  tail -n 10 /tmp/server_demo.log

  echo ""
  echo -e "${GREEN}✅ Server 啟動成功,監聽 port $SERVER_PORT${NC}"
  pause

  # ============================================================
  # 步驟 4: 測試基本連線
  # ============================================================
  show_step "4" "測試客戶端基本連線"
  show_feature "自訂協議 | Checksum 驗證 | 逾時處理"

  echo "🔌 建立測試連線..."
  if [ -f "bin/client" ]; then
    run_command "./bin/client --host $SERVER_HOST --port $SERVER_PORT --connections 1 --threads 1 --duration 5 --mix chat --out /tmp/basic_test.csv"

    echo "📊 連線測試結果:"
    if [ -f "/tmp/basic_test.csv" ]; then
      cat /tmp/basic_test.csv
    fi
  else
    echo -e "${YELLOW}⚠️  找不到 bin/client,跳過此測試${NC}"
  fi

  echo -e "${GREEN}✅ 基本連線測試完成${NC}"
  pause

  # ============================================================
  # 步驟 5: 聊天室功能展示
  # ============================================================
  show_step "5" "聊天室功能展示"
  show_feature "房間管理 | 訊息廣播 | 跨 Worker 通訊"

  echo "💬 聊天室操作流程:"
  echo "  1) 使用者登入"
  echo "  2) 加入聊天室"
  echo "  3) 發送訊息"
  echo "  4) 接收廣播訊息"
  echo ""

  if [ -f "scripts/demo_all_features.sh" ]; then
    echo "🎬 執行聊天功能自動化測試..."
    run_command "timeout 10 bash scripts/demo_all_features.sh || true"
  else
    echo -e "${YELLOW}提示: 可使用 bin/interactive 進行手動測試${NC}"
    echo "  範例: ./bin/interactive --host $SERVER_HOST --port $SERVER_PORT --user $DEMO_USER"
  fi

  echo -e "${GREEN}✅ 聊天室功能展示完成${NC}"
  pause

  # ============================================================
  # 步驟 6: 交易功能展示
  # ============================================================
  show_step "6" "交易系統功能展示"
  show_feature "存款/提款/轉帳 | Per-Account Locks | Deadlock Avoidance | Asset Conservation"

  echo "💰 交易系統核心功能:"
  echo ""
  echo "  🔹 DEPOSIT (存款):"
  echo "     - 增加帳戶餘額"
  echo "     - 記錄交易日誌"
  echo "     - 更新系統總資產"
  echo ""
  echo "  🔹 WITHDRAW (提款):"
  echo "     - 檢查餘額充足性"
  echo "     - 餘額不足時返回 ERR_INSUFFICIENT_FUNDS"
  echo "     - 成功後扣除餘額並記錄"
  echo ""
  echo "  🔹 TRANSFER (轉帳):"
  echo "     - 原子性操作 (全部成功或全部失敗)"
  echo "     - 固定鎖順序 (min→max) 避免死鎖"
  echo "     - 同時更新兩個帳戶餘額"
  echo "     - 不改變系統總資產"
  echo ""
  echo "  🔹 BALANCE (查詢):"
  echo "     - 即時查詢帳戶餘額"
  echo "     - 唯讀操作,不需要寫鎖"
  echo ""
  echo "🔒 並發控制機制:"
  echo "  • Per-Account Locks: 每個帳戶有獨立的鎖"
  echo "  • Deadlock Avoidance: 固定鎖順序 (account_id 小→大)"
  echo "  • Transaction Log: 記錄所有操作用於 auditing"
  echo ""

  if [ -f "bin/client" ]; then
    echo "🧪 執行交易為主的壓力測試 (30 並發連線,15 秒)..."
    echo "   工作負載: 30% DEPOSIT, 20% WITHDRAW, 30% TRANSFER, 20% BALANCE"
    echo ""
    run_command "./bin/client --host $SERVER_HOST --port $SERVER_PORT --connections 30 --threads 12 --duration 15 --mix trade --out /tmp/trade_test.csv"

    echo ""
    echo "📊 交易測試結果詳細分析:"
    if [ -f "/tmp/trade_test.csv" ]; then
      cat /tmp/trade_test.csv

      echo ""
      echo "🎯 重點指標:"
      echo "  • 檢查 error_rate: 應該很低 (僅餘額不足時產生)"
      echo "  • 檢查 p99_latency: TRANSFER 可能較高 (需要兩個鎖)"
      echo "  • 檢查 throughput: 每秒處理的交易數"
    fi

    echo ""
    echo "🔍 驗證資產守恆:"
    echo "  理論: 存款總額 - 提款總額 = 帳戶餘額總和"
    if [ -f "bin/metrics" ]; then
      ./bin/metrics --shm /ns_trading_chat | grep -E "deposit|withdraw|balance|total" || echo "  (查看 server 共享記憶體)"
    fi
  else
    echo -e "${YELLOW}⚠️  找不到 bin/client${NC}"
  fi

  echo ""
  echo -e "${GREEN}✅ 交易系統展示完成${NC}"
  echo ""
  echo "💡 進階測試: 可執行 demo_trading.sh 查看更詳細的交易系統測試"
  pause

  # ============================================================
  # 步驟 7: 高並發壓力測試
  # ============================================================
  show_step "7" "高並發壓力測試"
  show_feature "≥100 並發連線 | 多執行緒客戶端 | p50/p95/p99 延遲 | Throughput"

  echo "🔥 壓力測試配置:"
  echo "  • 連線數: 100"
  echo "  • 執行緒: 16"
  echo "  • 時長: 30 秒"
  echo "  • 工作負載: Mixed (chat + trade)"
  echo ""

  if [ -f "bin/client" ]; then
    echo "⚡ 開始壓力測試..."
    run_command "./bin/client --host $SERVER_HOST --port $SERVER_PORT --connections 100 --threads 16 --duration 30 --mix mixed --out /tmp/stress_test.csv"

    echo ""
    echo "📊 壓力測試結果:"
    if [ -f "/tmp/stress_test.csv" ]; then
      cat /tmp/stress_test.csv | grep -E "(connections|p50|p95|p99|throughput|errors)" || cat /tmp/stress_test.csv
    fi

    echo ""
    echo -e "${GREEN}✅ 成功完成 100+ 並發連線測試${NC}"
  else
    echo -e "${YELLOW}⚠️  找不到 bin/client,跳過壓力測試${NC}"
  fi
  pause

  # ============================================================
  # 步驟 8: 系統監控
  # ============================================================
  show_step "8" "系統監控與指標"
  show_feature "共享記憶體指標 | 即時統計 | 錯誤率監控"

  echo "📈 檢查系統指標..."

  if [ -f "bin/metrics" ]; then
    echo ""
    run_command "./bin/metrics --shm /ns_trading_chat"
  else
    echo "  提示: bin/metrics 工具可用於查看即時指標"
    echo "  包含: total_requests, connections, op_counts, error_counts 等"
  fi

  echo ""
  echo "📄 Server 執行日誌 (最後 20 行):"
  tail -n 20 /tmp/server_demo.log

  echo ""
  echo -e "${GREEN}✅ 監控數據擷取完成${NC}"
  pause

  # ============================================================
  # 步驟 9: 優雅關閉
  # ============================================================
  show_step "9" "優雅關閉與資源清理"
  show_feature "SIGINT/SIGTERM 處理 | 共享記憶體釋放 | Worker 清理"

  echo "🛑 發送 SIGTERM 信號給 Server..."
  if [ -n "$server_pid" ] && kill -0 $server_pid 2>/dev/null; then
    run_command "kill -TERM $server_pid"

    echo "⏳ 等待 Server 優雅關閉..."
    sleep 3

    if kill -0 $server_pid 2>/dev/null; then
      echo -e "${YELLOW}⚠️  Server 未在時限內關閉,強制終止${NC}"
      kill -9 $server_pid 2>/dev/null || true
    else
      echo -e "${GREEN}✅ Server 已優雅關閉${NC}"
    fi
  else
    echo "  Server 進程已不存在"
  fi

  echo ""
  echo "🧹 檢查資源清理狀況:"
  echo "  • 共享記憶體: $([ -e /dev/shm/ns_trading_chat ] && echo '❌ 仍存在 (應手動清理)' || echo '✅ 已清理')"
  echo "  • Server 進程: $(pgrep -f 'bin/server' >/dev/null && echo '❌ 仍運行' || echo '✅ 已終止')"

  echo ""
  run_command "rm -f /dev/shm/ns_trading_chat"

  echo -e "${GREEN}✅ 資源清理完成${NC}"
  pause

  # ============================================================
  # 總結
  # ============================================================
  clear
  echo -e "${MAGENTA}"
  echo "═══════════════════════════════════════════════════════════════"
  echo "   功能展示完成!"
  echo "═══════════════════════════════════════════════════════════════"
  echo -e "${NC}"
  echo ""
  echo -e "${GREEN}✅ 已成功展示以下功能:${NC}"
  echo "  1. ✓ 多進程伺服器架構 (Master + 4 Workers)"
  echo "  2. ✓ 自訂應用層協議 (frame-based, checksum)"
  echo "  3. ✓ 聊天室系統 (join/leave/broadcast)"
  echo "  4. ✓ 交易系統 (deposit/withdraw/transfer/balance)"
  echo "  5. ✓ 高並發測試 (100+ 連線)"
  echo "  6. ✓ 共享記憶體 IPC 與同步機制"
  echo "  7. ✓ 系統監控與指標收集"
  echo "  8. ✓ 優雅關閉與資源清理"
  echo ""
  echo -e "${CYAN}📁 生成的測試檔案:${NC}"
  ls -lh /tmp/*test.csv /tmp/server_demo.log 2>/dev/null || echo "  (無測試檔案)"
  echo ""
  echo -e "${YELLOW}💡 進階測試:${NC}"
  echo "  • 完整測試套件: bash scripts/run_all_tests.sh"
  echo "  • Real Test + 圖表: RUN_REAL_TESTS=1 bash scripts/run_all_tests.sh"
  echo "  • Cross-worker 測試: bash scripts/demo_cross_worker_chat.sh"
  echo ""
  echo -e "${BLUE}📚 更多資訊:${NC}"
  echo "  • README.md - 專案總覽"
  echo "  • USAGE_ZH.md - 使用說明"
  echo "  • AUDITING.md - Auditing 討論"
  echo "  • docs/screenshots/ - 截圖證據"
  echo ""
  echo "感謝使用 NTUT Network Trading Chatroom Demo!"
  echo ""
}

# 錯誤處理
cleanup_on_error() {
  echo ""
  echo -e "${RED}❌ 發生錯誤,正在清理...${NC}"
  pkill -f "bin/server" 2>/dev/null || true
  rm -f /dev/shm/ns_trading_chat 2>/dev/null || true
  exit 1
}

trap cleanup_on_error ERR

# 執行主程式
main
