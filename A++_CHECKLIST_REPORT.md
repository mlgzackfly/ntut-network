# A++ Done Criteria Checklist 檢查報告

根據 `README.md` 的 A++ Done Criteria Checklist，逐項檢查結果如下：

---

## ✅ 1) Repo & collaboration (must)

- [x] **GitHub**: repository 存在（本地 git repo 已初始化）
- [x] **Branch**: 預設分支為 `main`（git status 顯示 main）
- [x] **Conventional commits (English)**: 需檢查 commit 歷史（用戶規則要求符合約定式提交）
- [ ] **Roles**: README.md 中有 "Team Roles" 區塊（lines 316-329），但需確認是否準確反映實際分工
- [x] **Reproducibility**: README.md 有 build/run 說明，但需在 Linux 環境測試（macOS 會因 epoll 失敗）

**狀態**: ⚠️ **部分符合** - 需確認 commit 格式和 roles 準確性

---

## ✅ 2) Build system (hard requirement)

- [x] **Build file exists**: `Makefile` 存在於 repo root
- [x] **One-command build**: `make` 可產生 server 和 client
- [x] **Clean build**: `make clean && make` 可重複執行
- [x] **No forbidden dependencies**: 無 HTTP/WebSocket 庫（使用自訂協定）

**狀態**: ✅ **完全符合**（但需在 Linux 環境編譯，macOS 會因 `sys/epoll.h` 失敗）

---

## ✅ 3) Libraries / modularity (.a/.so shared by client & server)

- [x] **Shared libs implemented**: 
  - `libproto.a` (frame encode/decode, checksum)
  - `libnet.a` (socket wrappers, timeouts)
  - `liblog.a` (structured logging)
- [x] **Artifacts exist**: Makefile 會產生 `.a` 檔案
- [x] **Actually used**: server 和 client 都連結這些庫（見 Makefile lines 64-68）
- [x] **API boundary**: protocol encode/decode + checksum 都在 `libproto` 中

**狀態**: ✅ **完全符合**

---

## ✅ 4) Custom application-layer protocol (hard requirement)

- [x] **Not HTTP/WebSocket**: 使用自訂二進位 frame 格式（32-byte header + body）
- [x] **Header/body spec**: 
  - Header: magic(2) + version(1) + flags(1) + header_len(2) + body_len(4) + opcode(2) + status(2) + req_id(8) + checksum(4) + reserved(6)
  - Big-endian network byte order
  - 定義在 `include/proto.h` 和 README.md
- [x] **Frame correctness**: 
  - 處理 partial read/write（`worker.c` lines 343-405 有 frame reassembly）
  - 驗證 header basic fields 和 checksum
- [x] **Error handling**: 有完整的 status codes（`ST_ERR_BAD_PACKET`, `ST_ERR_CHECKSUM_FAIL`, `ST_ERR_UNAUTHORIZED`, etc.）

**狀態**: ✅ **完全符合**

---

## ✅ 5) Server: multi-process + IPC (hard requirement)

- [x] **Multi-process**: server 使用 `fork()` 產生多個 worker processes（`main.c` lines 132-145）
- [x] **Shared memory IPC**: 使用 `shm_open + mmap`（`shm_state.c` lines 21-57）
- [x] **Cross-process synchronization**: 使用 `PTHREAD_PROCESS_SHARED` mutexes（`shm_state.c` lines 81-95）
- [x] **Metrics in shared state**: 
  - `total_requests`, `total_connections`, `total_errors`
  - `op_counts[opcode]`
  - 使用 atomic operations（`worker.c` line 33: `__atomic_fetch_add`）

**狀態**: ✅ **完全符合**

---

## ✅ 6) Trading consistency (ACID-style expectations)

- [x] **Per-account locking**: 每個 account 有獨立的 mutex（`shm_state.h` line 54: `acct_mu[NS_MAX_USERS]`）
- [x] **Deadlock avoidance**: TRANSFER 使用固定鎖順序 `min(from,to)` 然後 `max(from,to)`（`worker.c` lines 304-319）
- [x] **Insufficient funds**: WITHDRAW/TRANSFER 正確拒絕並不會產生負餘額（`worker.c` lines 280-286, 311-312）
- [ ] **Invariant check (auditing)**: **缺失** - 沒有實作資產守恆檢查（sum of balances 一致性驗證）

**狀態**: ⚠️ **部分符合** - 缺少 invariant check

---

## ✅ 7) Chat correctness under multi-process

- [x] **Room membership**: join/leave 更新在 shared memory 中，使用 per-room mutex（`worker.c` lines 218-220, 231-233）
- [x] **Broadcast works across workers**: 
  - 使用 shared-memory ring buffer（`shm_state.h` lines 62-64）
  - 使用 eventfd/pipe 通知其他 workers（`main.c` lines 95-117）
  - Workers 輪詢新事件並推送給自己的 connections（`worker.c` lines 94-120, 460, 498）
- [ ] **Delivery evidence**: **缺失** - 沒有 demo script 或 screenshot 證明 cross-worker broadcast

**狀態**: ⚠️ **部分符合** - 實作正確但缺少證據

---

## ✅ 8) Client: high concurrency stress testing (hard requirement)

- [x] **Multi-threaded client**: 使用 pthread，可配置 threads 和 connections（`client/main.c` lines 347-361）
- [x] **≥100 concurrent connections**: 支援 `--connections` 參數，預設 100（`client/main.c` line 323）
- [x] **Workload mixes**: 支援 `mixed`, `trade-heavy`, `chat-heavy`（`client/main.c` lines 244-250）
- [x] **Metrics output**: 輸出 p50/p95/p99 latency 和 req/s 到 CSV（`client/main.c` lines 381-394）

**狀態**: ✅ **完全符合**

---

## ⚠️ 9) Security (choose ≥1; A++ recommends ≥2)

- [x] **Integrity**: CRC32 checksum 已實作並驗證（`proto.c` lines 55-71, `worker.c` line 371）
- [x] **Authentication**: LOGIN handshake 已實作（HELLO 返回 nonce，LOGIN 使用 CRC32(username||nonce) 作為 token）（`worker.c` lines 154-205）
- [ ] **(Optional) Encryption**: 未實作（`NS_FLAG_ENCRYPTED` 定義但未使用）

**狀態**: ✅ **符合 A++ 推薦（2/2）** - 有 Integrity + Authentication

---

## ⚠️ 10) Reliability (choose ≥1; A++ recommends 3)

### 10.1 Heartbeat
- [x] **Heartbeat opcode**: HEARTBEAT 已實作（`worker.c` lines 207-209）
- [ ] **Timeout detection**: **缺失** - 沒有追蹤 `last_seen` 時間戳
- [ ] **Session cleanup**: **缺失** - 沒有基於 timeout 清理 session/room membership/online status

### 10.2 Timeouts
- [x] **Socket timeouts API**: `net_set_timeouts_ms()` 已實作（`net.c` lines 47-60）
- [ ] **Server usage**: **缺失** - server worker 沒有設定 socket timeouts
- [ ] **ERR_SERVER_BUSY**: **缺失** - 沒有實作 server busy 檢測和返回此錯誤碼
- [ ] **Client backoff**: **缺失** - client 沒有 exponential backoff

### 10.3 Graceful shutdown
- [x] **SIGINT/SIGTERM handling**: 已實作（`main.c` lines 19-23, 74-75）
- [x] **Worker termination**: master 發送 SIGTERM 給 workers 並等待（`main.c` lines 158-163）
- [x] **IPC cleanup**: 關閉 shared memory 並 unlink（`main.c` line 173）
- [ ] **Drain existing connections**: **部分** - workers 在收到 SIGTERM 時會退出，但沒有明確的 "停止接受新請求，處理完現有請求後退出" 邏輯

**狀態**: ⚠️ **部分符合（1/3）** - 只有 Graceful shutdown 基本實作，缺少 Heartbeat timeout 和 Timeout handling

---

## ⚠️ 11) Real Test (A++ "plus" requirement)

- [x] **Metrics output**: client 輸出 latency (p50/p95/p99), throughput (req/s), error rate 到 CSV
- [x] **Test matrix script**: `scripts/run_real_tests.sh` 存在
- [x] **100 connections, mixed**: 已包含（`run_real_tests.sh` line 113）
- [x] **200 connections, trade-heavy**: 已包含（`run_real_tests.sh` line 121）
- [ ] **Payload sweep**: **缺失** - 沒有 32B → 256B → 1KB 的 payload size sweep
- [x] **Worker scaling**: 已包含 1/2/4/8 workers（`run_real_tests.sh` line 105）
- [x] **Artifacts**: gnuplot scripts 存在（`plot_latency.gp`, `plot_throughput.gp`）
- [ ] **CSV results**: **缺失** - `results/` 目錄只有 `.gitkeep`，沒有實際的 CSV 檔案
- [ ] **Plots**: **缺失** - 沒有生成的 PNG 圖檔

**狀態**: ⚠️ **部分符合** - 腳本完整但缺少 payload sweep 和實際執行結果

---

## ❌ 12) Auditing discussion (A++ "plus" requirement)

### 12.1 Protocol auditing
- [x] **Max body length**: 有 `max_body_len` 限制（`main.c` line 54: 65536，`worker.c` line 362 驗證）
- [x] **Frame reassembly**: 已實作 partial read/write（`worker.c` lines 343-386）
- [x] **Checksum failures**: 有計數和拒絕（`worker.c` lines 371-376）
- [x] **State machine**: 拒絕未登入的 trading/chat ops（`worker.c` lines 146-151）
- [ ] **Documentation**: **缺失** - 沒有文件說明這些設計決策

### 12.2 Concurrency auditing
- [x] **Deadlock prevention**: 固定鎖順序已實作（`worker.c` lines 304-319）
- [ ] **Invariant check**: **缺失** - 沒有資產守恆檢查實作
- [ ] **Documentation**: **缺失** - 沒有文件說明 deadlock 預防策略和測試結果

### 12.3 Fault injection
- [ ] **Kill worker recovery**: **缺失** - master 只記錄 worker 退出但不重啟（`main.c` line 152: "not restarting in MVP"）
- [ ] **Disconnect/reconnect**: **缺失** - 沒有測試或文件說明 heartbeat timeout 觸發的 cleanup
- [ ] **Graceful shutdown validation**: **缺失** - 沒有文件或證據證明 IPC cleanup

### 12.4 Performance auditing
- [ ] **Bottleneck analysis**: **缺失** - 沒有文件說明 p99 latency spikes 的原因（lock contention）
- [ ] **Improvements**: **缺失** - 沒有 before/after 比較或優化實作

**狀態**: ❌ **不符合** - 實作有基礎但完全缺少文件說明

---

## ❌ 13) Evidence (screenshots/logs)

- [ ] **Screenshots**: **缺失** - `docs/screenshots/` 只有 `.gitkeep`，沒有：
  - `server_start.png`（顯示 workers/PIDs）
  - `client_stress.png`（≥100 connections）
  - `metrics.png`（p95/p99 + req/s）
  - `graceful_shutdown.png`（SIGINT + clean exit）
- [x] **Logs format**: logs 包含 pid, opcode, req_id, status（`log.c` lines 37-45）

**狀態**: ❌ **不符合** - 完全缺少 screenshots

---

## 📊 總結

### 符合項目統計
- ✅ **完全符合**: 8 項（1, 2, 3, 4, 5, 8, 9）
- ⚠️ **部分符合**: 4 項（6, 7, 10, 11）
- ❌ **不符合**: 2 項（12, 13）

### 關鍵缺失項目（需補齊以達到 A++）

1. **Reliability (10)**: 
   - Heartbeat timeout detection + session cleanup
   - ERR_SERVER_BUSY 實作 + client exponential backoff
   - Socket timeout 實際使用

2. **Auditing discussion (12)**:
   - 撰寫文件說明 protocol auditing、concurrency auditing、fault injection、performance auditing
   - 實作 worker restart 機制（fault injection）
   - 實作資產守恆 invariant check

3. **Real Test (11)**:
   - 補齊 payload sweep 測試
   - 實際執行測試並提交 CSV 和 plots

4. **Evidence (13)**:
   - 補齊所有要求的 screenshots

5. **其他小項**:
   - Trading consistency (6): 資產守恆檢查
   - Chat correctness (7): cross-worker broadcast 證據

---

## 🔧 建議優先順序

### 高優先級（A++ 必須）
1. 補齊 Auditing discussion 文件（12）
2. 補齊 Evidence screenshots（13）
3. 實作 Heartbeat timeout + cleanup（10.1）
4. 實作 worker restart 機制（12.3）

### 中優先級（A++ 推薦）
5. 實作 ERR_SERVER_BUSY + client backoff（10.2）
6. 補齊 payload sweep 測試（11）
7. 實作資產守恆檢查（6, 12.2）

### 低優先級（加分項）
8. 實作 payload encryption（9）
9. 優化 lock granularity 並提供 before/after 數據（12.4）
