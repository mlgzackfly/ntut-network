# Screenshots Documentation

本目錄應包含以下執行時截圖，作為專案功能的證據。

## 必需的截圖

### 1. `server_start.png`
**說明**：顯示伺服器啟動時的狀態，包括：
- Master 行程與多個 Worker 行程的 PID
- 伺服器日誌輸出（顯示 workers 啟動資訊）
- 可以使用 `ps aux | grep server` 或 `htop` 顯示行程樹

**產生方法**：
```bash
# 啟動伺服器
./bin/server --port 9000 --workers 4

# 在另一個終端查看行程
ps aux | grep server

# 或使用 htop/pstree
pstree -p $(pgrep -f "bin/server" | head -1)
```

### 2. `client_stress.png`
**說明**：顯示客戶端壓力測試執行情況，包括：
- 至少 100 個併發連線
- 測試統計輸出（connections, threads, duration, total, ok, err, rps, p50/p95/p99）
- 可以使用 `netstat -an | grep :9000` 或 `ss -tn | grep :9000` 顯示連線數

**產生方法**：
```bash
# 在一個終端執行伺服器
./bin/server --port 9000 --workers 4

# 在另一個終端執行客戶端
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 30 --mix mixed

# 同時查看連線數
watch -n 1 'ss -tn | grep :9000 | wc -l'
```

### 3. `metrics.png`
**說明**：顯示效能指標，包括：
- p50/p95/p99 延遲數據
- 吞吐量 (req/s)
- 可以從 CSV 輸出或客戶端終端輸出中截圖
- 也可以使用 gnuplot 產生的圖表

**產生方法**：
```bash
# 執行測試並產生 CSV
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 60 --mix mixed --out results/test.csv

# 查看 CSV 內容
cat results/test.csv

# 或產生圖表
gnuplot -c scripts/plot_latency.gp results/test.csv results/latency.png
gnuplot -c scripts/plot_throughput.gp results/test.csv results/throughput.png
```

### 4. `graceful_shutdown.png`
**說明**：顯示優雅關閉過程，包括：
- 傳送 SIGINT 訊號
- 伺服器日誌顯示 "Shutting down..."
- Workers 正常退出
- Shared memory 被清理（`ls /dev/shm/ns_trading_chat` 應該不存在）

**產生方法**：
```bash
# 啟動伺服器
./bin/server --port 9000 --workers 4

# 在另一個終端傳送 SIGINT
kill -INT $(pgrep -f "bin/server" | head -1)

# 觀察伺服器日誌輸出
# 檢查 shared memory 是否被清理
ls /dev/shm/ns_trading_chat  # 應該不存在
```

## 功能展示截圖 (Features Showcase)

為了豐富 `docs/FEATURES_SHOWCASE.md`，建議產生以下截圖。您可以使用輔助腳本來產生這些畫面：

```bash
bash scripts/generate_screenshot_content.sh
```

### 5. `trading_flow.png`
- **內容**：展示 Login -> Deposit -> Transfer -> Balance 的完整流程。
- **產生**：執行腳本選 Option 1。

### 6. `trading_error.png`
- **內容**：展示餘額不足與用戶不存在的錯誤訊息。
- **產生**：執行腳本選 Option 2。

### 7. `chat_broadcast.png`
- **內容**：展示多用戶聊天室對話。
- **產生**：執行腳本選 Option 3。

### 8. `shm_metrics.png`
- **內容**：展示詳細的系統指標與資產守恆狀態。
- **產生**：執行腳本選 Option 4。

## 截圖要求

- **格式**：PNG 或 JPEG
- **解析度**：建議至少 1280x720，確保文字清晰可讀
- **內容**：應包含足夠的上下文資訊（終端視窗、指令、輸出等）
- **命名**：使用上述檔名

## 替代方案

如果暫時無法產生實際截圖，可以：
1. 提供終端輸出的文字日誌（儲存為 `.txt` 檔）
2. 提供 CSV 資料檔作為證據
3. 在文件中說明截圖產生步驟，供 TA／Instructor 驗證

## 验证清单

- [ ] `server_start.png` - 顯示多個 worker 行程
- [ ] `client_stress.png` - 顯示 ≥100 併發連線
- [ ] `metrics.png` - 顯示 p50/p95/p99 與 req/s
- [ ] `graceful_shutdown.png` - 顯示優雅關閉與資源清理
- [ ] `trading_flow.png` - 交易流程展示
- [ ] `trading_error.png` - 錯誤處理展示
- [ ] `chat_broadcast.png` - 聊天功能展示
- [ ] `shm_metrics.png` - 系統指標展示

---

**注意**：前 4 張截圖是 A++ 檢查清單的要求項（第 13 項）。後 4 張是用於功能展示的加分項。

