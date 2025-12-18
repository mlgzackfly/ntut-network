# 使用說明文件

## 專案概述

本專案實作了一個**高並發客戶端-伺服器網路服務系統**，結合了聊天室和交易/銀行功能。系統採用自訂應用層協定，使用多進程架構和共享記憶體 IPC，支援高並發連線和可靠性機制。

### 主要功能

- **聊天功能**：用戶登入、加入/離開房間、群組訊息、伺服器推送（廣播）
- **交易功能**：存款（DEPOSIT）、提款（WITHDRAW）、轉帳（TRANSFER）、查詢餘額（BALANCE）

### 技術特點

- **多進程架構**：Master-Worker 模式，支援多個 worker 進程並發處理連線
- **共享記憶體 IPC**：使用 POSIX shared memory 和 process-shared mutexes 進行跨進程同步
- **自訂協定**：32 字節固定 header + 可變 body，使用 CRC32 checksum 驗證
- **可靠性機制**：Heartbeat timeout、socket timeout、優雅關閉、worker 自動重啟
- **高並發測試**：多執行緒客戶端，支援 ≥100 並發連線

---

## 系統需求

- **作業系統**：Linux（需要 epoll、eventfd、SO_REUSEPORT 支援）
- **編譯器**：GCC（支援 C11）
- **工具**：make、gnuplot（用於繪圖）
- **依賴**：pthread（POSIX threads）

---

## 編譯

### 基本編譯

```bash
# 清理舊的編譯產物
make clean

# 編譯所有目標（server、client、靜態庫）
make

# 或使用並行編譯加速
make -j
```

### 編譯產物

編譯完成後，會在以下目錄產生檔案：

- `bin/server`：伺服器執行檔
- `bin/client`：客戶端執行檔（壓力測試工具）
- `lib/libproto.a`：協定處理靜態庫
- `lib/libnet.a`：網路功能靜態庫
- `lib/liblog.a`：日誌功能靜態庫

---

## 執行伺服器

### 基本用法

```bash
./bin/server [選項]
```

### 選項說明

- `--bind <IP>`：綁定的 IP 位址（預設：0.0.0.0，即所有介面）
- `--port <PORT>`：監聽的埠號（預設：9000）
- `--workers <N>`：Worker 進程數量（預設：4）
- `--shm <NAME>`：Shared memory 名稱（預設：/ns_trading_chat）
- `--help`：顯示幫助訊息

### 範例

```bash
# 使用預設設定啟動伺服器（4 個 workers，埠號 9000）
./bin/server

# 指定埠號和 worker 數量
./bin/server --port 8080 --workers 8

# 綁定到特定 IP
./bin/server --bind 192.168.1.100 --port 9000
```

### 伺服器輸出

伺服器啟動後會輸出日誌到 stderr，包含：
- 啟動資訊（port、workers、shared memory 名稱）
- Worker 進程的 PID
- 連線和請求處理資訊
- 錯誤和警告訊息

範例輸出：
```
2024-12-12 10:00:00.123 [server] pid=12345 INFO server/main.c:119: Server starting: port=9000 workers=4 shm=/ns_trading_chat
2024-12-12 10:00:00.124 [server-w0] pid=12346 INFO worker.c:450: Worker started (pid=12346)
2024-12-12 10:00:00.125 [server-w1] pid=12347 INFO worker.c:450: Worker started (pid=12347)
...
```

### 停止伺服器

按 `Ctrl+C` 或發送 `SIGINT`/`SIGTERM` 信號：

```bash
# 發送 SIGINT
kill -INT <master_pid>

# 或發送 SIGTERM
kill -TERM <master_pid>
```

伺服器會優雅關閉：
1. 停止接受新連線
2. 通知所有 workers 停止
3. 等待現有請求處理完成（最多 5 秒）
4. 清理 shared memory 和其他資源

---

## 執行客戶端（壓力測試）

### 基本用法

```bash
./bin/client [選項]
```

### 選項說明

- `--host <HOST>`：伺服器 IP 位址（預設：127.0.0.1）
- `--port <PORT>`：伺服器埠號（預設：9000）
- `--connections <N>`：總連線數（預設：100）
- `--threads <N>`：執行緒數量（預設：16）
- `--duration <SEC>`：測試持續時間（秒）（預設：30）
- `--mix <TYPE>`：工作負載類型（預設：mixed）
  - `mixed`：混合負載（聊天 + 交易）
  - `trade-heavy`：交易為主（80% 交易操作）
  - `chat-heavy`：聊天為主（70% 聊天操作）
- `--out <FILE>`：輸出 CSV 檔案路徑（預設：results.csv）
- `--help`：顯示幫助訊息

### 範例

```bash
# 基本壓力測試（100 連線，30 秒，mixed 負載）
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 30 --mix mixed --out results.csv

# 高並發測試（200 連線，trade-heavy）
./bin/client --connections 200 --threads 32 --duration 60 --mix trade-heavy --out trade_heavy.csv

# 長時間測試（5 分鐘）
./bin/client --duration 300 --out long_test.csv
```

### 客戶端輸出

客戶端會輸出統計資訊到 stdout，並將詳細結果寫入 CSV 檔案。

**Console 輸出範例**：
```
connections=100 threads=16 duration=30 total=45230 ok=45120 err=110 rps=1507.67 p50=1250us p95=3200us p99=8500us
```

**CSV 輸出格式**：
```csv
host,port,connections,threads,duration_s,total,ok,err,rps,p50_us,p95_us,p99_us
127.0.0.1,9000,100,16,30,45230,45120,110,1507.67,1250,3200,8500
```

欄位說明：
- `host`：伺服器主機
- `port`：伺服器埠號
- `connections`：總連線數
- `threads`：執行緒數
- `duration_s`：測試持續時間（秒）
- `total`：總請求數
- `ok`：成功請求數
- `err`：錯誤請求數
- `rps`：每秒請求數（throughput）
- `p50_us`：50% 分位數延遲（微秒）
- `p95_us`：95% 分位數延遲（微秒）
- `p99_us`：99% 分位數延遲（微秒）

---

## 執行完整測試套件

專案提供了自動化測試腳本，可以執行多種測試場景並生成圖表。

### 執行測試

```bash
# 執行完整測試矩陣
bash scripts/run_real_tests.sh

# 自訂參數
HOST=127.0.0.1 PORT=9000 DURATION=60 bash scripts/run_real_tests.sh
```

### 測試內容

腳本會自動執行以下測試：

1. **Worker Scaling 測試**：
   - Workers: 1, 2, 4, 8
   - 每個 worker 配置下執行：
     - 100 連線，mixed 負載
     - 200 連線，trade-heavy 負載

2. **Payload Size Sweep**：
   - Payload sizes: 32B, 256B, 1024B
   - Workers: 4，Connections: 100

### 測試輸出

測試完成後會產生：

- `results/runs.csv`：所有測試結果的彙總 CSV
- `results/server.log`：伺服器日誌
- `results/tmp-*.csv`：各次測試的臨時 CSV 檔案

### 生成圖表

使用 gnuplot 生成延遲和吞吐量圖表：

```bash
# 生成延遲圖表
gnuplot -c scripts/plot_latency.gp results/runs.csv results/latency.png

# 生成吞吐量圖表
gnuplot -c scripts/plot_throughput.gp results/runs.csv results/throughput.png
```

**注意**：需要安裝 gnuplot：
```bash
# Ubuntu/Debian
sudo apt-get install gnuplot

# CentOS/RHEL
sudo yum install gnuplot

# macOS
brew install gnuplot
```

---

## 協定說明

### Frame 格式

每個 frame 由固定 32 字節 header 和可變長度 body 組成：

**Header（32 bytes，big-endian）**：
```
magic (2)        : 0x4E53 ("NS")
version (1)      : 1
flags (1)        : bit0=encrypted, bit1=compressed, bit2=is_response
header_len (2)   : 32
body_len (4)     : body 長度（字節）
opcode (2)       : 操作碼
status (2)       : 狀態碼（response 使用）
req_id (8)       : 請求 ID（客戶端遞增）
checksum (4)     : CRC32(header_without_checksum + body)
reserved (6)     : 保留欄位（全 0）
```

### OpCodes

**認證/連線**：
- `0x0001`：HELLO（握手）
- `0x0002`：LOGIN（登入）
- `0x0003`：LOGOUT（登出）
- `0x0004`：HEARTBEAT（心跳）

**聊天**：
- `0x0101`：JOIN_ROOM（加入房間）
- `0x0102`：LEAVE_ROOM（離開房間）
- `0x0103`：CHAT_SEND（發送訊息）
- `0x0104`：CHAT_BROADCAST（伺服器推送）

**交易**：
- `0x0201`：DEPOSIT（存款）
- `0x0202`：WITHDRAW（提款）
- `0x0203`：TRANSFER（轉帳）
- `0x0204`：BALANCE（查詢餘額）

### Status Codes

- `0x0000`：OK（成功）
- `0x0001`：ERR_BAD_PACKET（無效封包）
- `0x0002`：ERR_CHECKSUM_FAIL（Checksum 驗證失敗）
- `0x0003`：ERR_UNAUTHORIZED（未授權）
- `0x0004`：ERR_NOT_FOUND（未找到）
- `0x0005`：ERR_INSUFFICIENT_FUNDS（餘額不足）
- `0x0006`：ERR_SERVER_BUSY（伺服器忙碌）
- `0x0007`：ERR_TIMEOUT（逾時）

### 認證流程

1. **HELLO**：客戶端發送 HELLO，伺服器返回 `server_nonce`
2. **LOGIN**：客戶端發送 `LOGIN(username, token)`，其中 `token = CRC32(username || server_nonce)`
3. 伺服器驗證 token，成功則返回 `user_id` 和初始餘額

---

## 常見問題

### Q1: 編譯失敗，找不到 `sys/epoll.h`

**A**: 本專案僅支援 Linux。macOS 不支援 epoll，請在 Linux 環境編譯執行。

### Q2: 執行時出現 "Address already in use"

**A**: 埠號已被佔用。解決方法：
- 更換埠號：`./bin/server --port 9001`
- 或終止佔用該埠的進程：`sudo lsof -i :9000` 然後 `kill <PID>`

### Q3: Shared memory 無法創建

**A**: 檢查：
- `/dev/shm` 目錄權限
- 是否有足夠的共享記憶體空間：`df -h /dev/shm`
- 清理舊的 shared memory：`rm /dev/shm/ns_trading_chat`

### Q4: 客戶端連線失敗

**A**: 檢查：
- 伺服器是否正在運行
- 防火牆是否阻擋連線
- IP 和埠號是否正確
- 伺服器日誌中的錯誤訊息

### Q5: 測試結果的 p99 latency 很高

**A**: 這是正常的，特別是在 trade-heavy 負載下：
- TRANSFER 操作需要鎖定兩個帳戶，可能產生鎖競爭
- 增加 workers 數量對 trade-heavy 的改善有限（因為鎖是跨 worker 的）
- 這是系統設計的權衡，確保交易正確性的同時犧牲部分性能

### Q6: Worker 進程異常退出

**A**: 檢查：
- 系統資源是否充足（記憶體、檔案描述符）
- 查看伺服器日誌中的錯誤訊息
- Master 會自動重啟 worker，但頻繁重啟可能表示有問題

### Q7: 如何查看系統指標？

**A**: 指標存儲在 shared memory 中，可以：
- 查看伺服器日誌（會定期輸出指標）
- 使用 `ipcs -m` 查看 shared memory 資訊
- 實作一個工具程式讀取 shared memory 並輸出指標

---

## 進階使用

### 自訂配置

可以修改 `src/server/main.c` 中的預設配置：

```c
cfg.max_connections_per_worker = 1000;  // 每個 worker 最大連線數
cfg.recv_timeout_ms = 30000;            // 接收 timeout（毫秒）
cfg.send_timeout_ms = 30000;            // 發送 timeout（毫秒）
```

### 資產守恆檢查

系統提供了資產守恆檢查函數，可用於驗證交易正確性：

```c
#include "shm_state.h"

int64_t current, expected;
if (ns_check_asset_conservation(shm, &current, &expected) != 0) {
    printf("資產守恆違反: current=%lld expected=%lld\n", 
           (long long)current, (long long)expected);
}
```

### 擴展功能

如需擴展功能，可以：
1. 新增 opcode（在 `include/proto.h` 中定義）
2. 在 `src/server/worker.c` 的 `handle_request()` 中處理新 opcode
3. 更新客戶端以支援新操作

---

## 故障排除

### 檢查系統資源

```bash
# 檢查檔案描述符限制
ulimit -n

# 檢查共享記憶體
ipcs -m

# 檢查進程
ps aux | grep server
```

### 調試模式

編譯時使用 debug 模式：

```bash
make clean
make CFLAGS="-O0 -g -DDEBUG"
```

然後使用 gdb 調試：

```bash
gdb ./bin/server
(gdb) run --port 9000 --workers 2
```

### 日誌級別

目前日誌級別固定為 INFO。如需修改，編輯 `src/common/log.c`：

```c
static log_level_t g_level = LOG_LEVEL_DEBUG;  // 改為 DEBUG 顯示更多資訊
```

---

## 參考文件

- `README.md`：專案概述和 A++ 檢查清單
- `AUDITING.md`：審計討論文件（協議、並發、故障注入、性能分析）
- `PROJECT_A++_SPEC.md`：A++ 規格文件
- `FINAL_PROJECT.md`：原始需求文件

---

## 聯絡與支援

如有問題或建議，請參考專案文件或聯繫開發團隊。

---

**最後更新**：2024-12-12
