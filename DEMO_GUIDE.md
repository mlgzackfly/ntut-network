# NTUT Network Trading Chatroom - Demo 腳本使用指南

此目錄包含三個 demo 腳本,用於展示專案的完整功能。所有腳本都使用 tmux 進行多窗格管理,方便同時觀察 server 和 client 的運作。

## 📁 腳本清單

| 腳本名稱 | 用途 | 執行時間 |
|---------|------|---------|
| `demo_ntut_network.sh` | 完整自動化 demo,適合快速展示 | 2-3 分鐘 |
| `demo_features.sh` | 逐步展示各項功能,適合課堂演示 | 10-15 分鐘 |
| `demo_cross_worker.sh` | 專門展示跨 Worker 廣播,需手動互動 | 5-10 分鐘 |

---

## 🚀 快速開始

### 前置需求

```bash
# 安裝 tmux
sudo apt-get update
sudo apt-get install tmux

# 確認在專案根目錄
cd /path/to/ntut-network

# 建置專案
make -j
```

### 腳本 1: 完整自動化 Demo (`demo_ntut_network.sh`)

**適合場景**: 快速展示、錄製 demo 影片、首次測試

**特點**:
- ✅ 全自動執行,無需手動操作
- ✅ 4 窗格布局: 控制面板 | Server | 互動 Client | 壓測 Client
- ✅ 即時顯示 metrics 監控
- ✅ 同時展示多個客戶端場景

**執行步驟**:

```bash
# 1. 給予執行權限
chmod +x demo_ntut_network.sh

# 2. 執行腳本 (會自動建置、啟動 tmux)
./demo_ntut_network.sh

# 3. 附加到 tmux session
tmux attach -t ntut-network-demo

# 4. 觀察各窗格的運行狀況
#    - 左上: 控制面板與即時 metrics
#    - 左下: Server 多進程日誌
#    - 右上: 互動式客戶端 (UserA)
#    - 右下: 壓力測試客戶端 (100 連線)

# 5. 結束 demo
tmux kill-session -t ntut-network-demo
```

**tmux 快捷鍵**:
- `Ctrl+B` 然後 `方向鍵`: 切換窗格
- `Ctrl+B` 然後 `[`: 進入捲動模式 (查看歷史)
- `Ctrl+B` 然後 `d`: 離開但保持 session 運行
- `Ctrl+B` 然後 `:`: 進入命令模式

**預期輸出**:
- Server 顯示 4 個 Worker 進程啟動
- 互動客戶端執行登入、交易操作
- 壓測客戶端顯示 100 連線的延遲/throughput 統計
- 控制面板即時更新 metrics (total_requests, op_counts 等)

---

### 腳本 2: 逐步功能展示 (`demo_features.sh`)

**適合場景**: 課堂演示、詳細說明、拍攝教學影片

**特點**:
- ✅ 分步驟展示,每步需按 Enter 確認
- ✅ 詳細的功能說明與技術重點
- ✅ 包含建置、測試、監控、清理全流程
- ✅ 適合邊執行邊講解

**執行步驟**:

```bash
# 1. 給予執行權限
chmod +x demo_features.sh

# 2. 執行腳本 (會逐步引導)
./demo_features.sh

# 3. 按照螢幕提示按 Enter 繼續每個步驟
# 步驟包含:
#   - 步驟 1: 環境檢查與建置
#   - 步驟 2: 清理舊資源
#   - 步驟 3: 啟動多進程伺服器
#   - 步驟 4: 基本連線測試
#   - 步驟 5: 聊天室功能
#   - 步驟 6: 交易系統
#   - 步驟 7: 高並發壓力測試 (100 連線)
#   - 步驟 8: 系統監控與指標
#   - 步驟 9: 優雅關閉與清理
```

**輸出檔案**:
```
/tmp/basic_test.csv      # 基本連線測試結果
/tmp/trade_test.csv      # 交易測試結果
/tmp/stress_test.csv     # 壓力測試結果 (100 連線)
/tmp/server_demo.log     # Server 完整日誌
```

**展示重點**:
- 每個步驟都有清楚的 "功能重點" 說明
- 自動執行測試並顯示結果
- 適合用於產生 A++ 所需的各類截圖證據

---

### 腳本 3: Cross-Worker 廣播展示 (`demo_cross_worker.sh`)

**適合場景**: 證明跨 Worker 通訊、A++ 評分要求

**特點**:
- ✅ 證明不同 Worker 間的聊天訊息廣播
- ✅ 3 窗格布局: Server 日誌 | Client 1 | Client 2
- ✅ 需手動在兩個客戶端窗格互動
- ✅ 適合拍攝截圖作為證據

**執行步驟**:

```bash
# 1. 給予執行權限
chmod +x demo_cross_worker.sh

# 2. 執行腳本
./demo_cross_worker.sh

# 3. 附加到 tmux session
tmux attach -t cross-worker-demo

# 4. 在 tmux 中操作:
#    a) 使用 Ctrl+B + 方向鍵 切換到中間窗格 (Client 1)
#    b) 執行: ./bin/interactive --host 127.0.0.1 --port 9000 --user Alice
#    c) 在 Client 1 執行:
#       > login
#       > join trading_room
#       > chat Hello from Alice!
#
#    d) 使用 Ctrl+B + 方向鍵 切換到右側窗格 (Client 2)
#    e) 執行: ./bin/interactive --host 127.0.0.1 --port 9000 --user Bob
#    f) 在 Client 2 執行:
#       > login
#       > join trading_room
#       > chat Hi Alice, this is Bob!
#
#    g) 切換回左側窗格查看 Server 日誌
#       - 觀察兩條訊息可能由不同 Worker PID 處理
#       - 但兩個 client 都能收到彼此的訊息

# 5. 截圖整個 tmux 畫面作為證據

# 6. 結束 demo
tmux kill-session -t cross-worker-demo
```

**驗證要點**:
- ✅ Server 日誌顯示不同 Worker PID 處理不同連線
- ✅ Alice 的訊息能被 Bob 收到 (即使在不同 Worker)
- ✅ Bob 的訊息能被 Alice 收到
- ✅ 證明共享記憶體 broadcast 機制運作正常

**截圖建議**:
```
docs/screenshots/cross_worker_broadcast.png
```
應包含:
- 左側: Server 日誌 (顯示 Worker PIDs)
- 中間: Client 1 的聊天畫面
- 右側: Client 2 的聊天畫面
- 清楚顯示訊息在不同 Worker 間傳遞

---

## 🎬 Demo 場景選擇指南

### 快速測試 (< 5 分鐘)
```bash
./demo_ntut_network.sh
tmux attach -t ntut-network-demo
# 觀察各窗格運行,確認無錯誤後截圖
```

### 課堂 Demo (10-15 分鐘)
```bash
./demo_features.sh
# 按照步驟逐一展示,邊執行邊講解
```

### 證明 Cross-Worker 通訊 (A++ 要求)
```bash
./demo_cross_worker.sh
tmux attach -t cross-worker-demo
# 手動在兩個客戶端互動,拍攝完整截圖
```

---

## 🐛 常見問題排除

### 問題 1: `tmux` 指令找不到
```bash
sudo apt-get install tmux
```

### 問題 2: Port 9000 被佔用
```bash
# 方法 1: 檢查並終止佔用進程
sudo lsof -i :9000
sudo kill -9 <PID>

# 方法 2: 修改腳本中的 SERVER_PORT 變數
```

### 問題 3: 共享記憶體清理失敗
```bash
# 手動清理
rm -f /dev/shm/ns_trading_chat

# 或修改腳本中的 SHM_NAME 變數
```

### 問題 4: `bin/interactive` 不存在
```bash
# 檢查 Makefile 是否包含 interactive target
make interactive

# 或使用 bin/client 替代
./bin/client --host 127.0.0.1 --port 9000 --connections 1
```

### 問題 5: Server 啟動失敗
```bash
# 檢查日誌
cat /tmp/server_demo.log
# 或
cat /tmp/cross_worker_server.log

# 常見原因:
# - Port 被佔用
# - 共享記憶體權限問題
# - Worker 數量超過系統限制
```

---

## 📸 截圖清單 (A++ 要求)

使用這些腳本可以產生以下證據截圖:

| 截圖檔名 | 來源腳本 | 內容 |
|---------|---------|------|
| `server_start.png` | `demo_features.sh` 步驟 3 | 顯示 4 個 Worker PIDs |
| `client_stress.png` | `demo_features.sh` 步驟 7 | 100+ 連線壓測畫面 |
| `metrics.png` | `demo_ntut_network.sh` 控制面板 | 即時 metrics 統計 |
| `graceful_shutdown.png` | `demo_features.sh` 步驟 9 | SIGTERM 處理與清理 |
| `cross_worker_broadcast.png` | `demo_cross_worker.sh` | 跨 Worker 訊息廣播 |
| `latency.png` | 手動執行 gnuplot | p50/p95/p99 延遲圖表 |
| `throughput.png` | 手動執行 gnuplot | Throughput 趨勢圖 |

---

## 🔧 進階使用

### 自訂測試參數

編輯腳本中的配置區段:

```bash
# demo_ntut_network.sh
SERVER_PORT=9000        # 改為其他 port
WORKERS=8               # 增加 worker 數量
SHM_NAME="/my_shm"      # 使用不同的共享記憶體名稱

# demo_features.sh
# 修改壓力測試參數 (步驟 7)
./bin/client --connections 200 --threads 32 --duration 60 ...
```

### 整合到 CI/CD

```bash
# 無人值守模式 (跳過互動)
timeout 60 ./demo_features.sh < /dev/null

# 檢查輸出檔案
if [ -f /tmp/stress_test.csv ]; then
    echo "Test passed"
else
    echo "Test failed"
    exit 1
fi
```

### 與其他測試整合

```bash
# 組合使用
./demo_ntut_network.sh          # 快速功能檢查
bash scripts/run_all_tests.sh   # 完整測試套件
RUN_REAL_TESTS=1 bash scripts/run_all_tests.sh  # 含 Real Test
```

---

## 📚 相關文件

- `README.md` - 專案總覽
- `USAGE_ZH.md` - 詳細使用說明
- `scripts/run_all_tests.sh` - 完整測試套件
- `docs/screenshots/README.md` - 截圖說明

---

## 🤝 貢獻

如有改進建議或發現問題,請提交 Issue 或 Pull Request。

---

**祝 Demo 順利!** 🎉
