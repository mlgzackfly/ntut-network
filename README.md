# Final Project: Trading Chatroom (High-Concurrency Client-Server System)

This project implements a **high-concurrency client-server network service** combining:

- **Chatroom**: login, join rooms, group messaging, server push (broadcast)
- **Trading/Banking**: `DEPOSIT / WITHDRAW / TRANSFER / BALANCE`

Key OS/architecture focus:

- **Client**: multi-threaded stress testing (≥ 100 concurrent connections)
- **Server**: multi-process architecture
- **IPC**: shared memory for state synchronization and counters (with locking)
- **Custom application-layer protocol** (HTTP/WebSocket are prohibited)
- **Security / Reliability**: checksum, (optional) authentication, heartbeat, timeout, graceful shutdown
- **A++ extras**: Real Test + Auditing discussion (fault injection + analysis)

> 🚀 **New!** Check out our [**Features Showcase**](docs/FEATURES_SHOWCASE.md) to see the trading system in action!

---

## Quick Start（快速開始）

> 詳細說明請參考 `USAGE_ZH.md`；本段提供一條龍跑完建置、功能展示、測試與結果產生的最短路徑。

1. **建置專案**

```bash
make -j
```

2. **啟動伺服器 + 基本互動測試（選擇其一）**

- **手動模式（適合課堂 Demo）**
  - 終端 1：
    ```bash
    ./bin/server --port 9000 --workers 4 --shm /ns_trading_chat
    ```
  - 終端 2（互動式 client，用來操作聊天＋交易）：
    ```bash
    ./bin/interactive --host 127.0.0.1 --port 9000 --user userA
    ```
- **自動功能展示腳本**
  ```bash
  bash scripts/demo_all_features.sh
  ```
  會依序展示：登入、房間加入、聊天、交易操作、錯誤處理等流程。

3. **Cross-worker 聊天廣播 Demo（證明跨 worker broadcast）**

```bash
bash scripts/demo_cross_worker_chat.sh
```

依螢幕指示在兩個額外終端各跑一個 `./bin/interactive`，互相聊天即可截圖作為 cross-worker broadcast 證據。

4. **執行所有測試（含單元＋系統測試，可選擇是否跑 Real Test）**

- **不含長時間 Real Test（較快）**
  ```bash
  bash scripts/run_all_tests.sh
  ```
- **包含 Real Test + 自動產生圖表**
  ```bash
  RUN_REAL_TESTS=1 bash scripts/run_all_tests.sh
  ```
  產出：
  - `results/runs.csv`（所有測試彙總）
  - `results/latency.png`、`results/throughput.png`（p50/p95/p99 與 throughput 圖）

5. **手動執行 Real Test（需要更細緻控制時）**

```bash
bash scripts/run_real_tests.sh
gnuplot -c scripts/plot_latency.gp results/runs.csv results/latency.png
gnuplot -c scripts/plot_throughput.gp results/runs.csv results/throughput.png
```

6. **截圖與交付證據**

- 依照 `docs/screenshots/README.md` 指示，生成並存放下列檔案於 `docs/screenshots/`：
  - `server_start.png`（顯示多個 worker/PID）
  - `client_stress.png`（≥100 連線壓測）
  - `metrics.png`（p95/p99 + req/s 或圖表）
  - `graceful_shutdown.png`（SIGINT 優雅關閉與 IPC 清理）

---

## Project Goal

Build a client-server system with high concurrency, a custom protocol, and reliability/security mechanisms, demonstrating mastery of OS primitives (**Process / Thread / IPC**) and solid software architecture design.

---

## Application Overview

### What can you do?

- **Chat**
  - user login
  - join/leave rooms
  - send messages to a room
  - receive server broadcast (push)

- **Trading**
  - deposit `DEPOSIT`
  - withdraw `WITHDRAW`
  - transfer `TRANSFER`
  - query balance `BALANCE`

### Why combine trading with chat?

Trading under multi-process concurrency naturally exposes race conditions and consistency challenges (e.g., simultaneous transfers/withdrawals), which is ideal for showcasing:

- shared-memory state sharing
- correctness of locks/semaphores
- deadlock avoidance
- auditing (invariants, fault injection, performance bottleneck analysis)

---

## Flow Explanation

### Login & join room

```mermaid
sequenceDiagram
  participant C as Client(thread)
  participant W as Server Worker(process)
  participant SHM as Shared Memory
  C->>W: TCP connect + HELLO/LOGIN
  W->>SHM: set user online, create session state
  W-->>C: LOGIN_RESP(OK)
  C->>W: JOIN_ROOM(room_id)
  W->>SHM: update room members
  W-->>C: JOIN_ROOM_RESP(OK)
```

### Trading (TRANSFER: fixed lock order avoids deadlock)

```mermaid
sequenceDiagram
  participant C as Client
  participant W as Worker
  participant SHM as Shared Memory (balances + locks + txn_log)
  C->>W: TRANSFER(to, amount, req_id)
  W->>SHM: lock account[min], lock account[max]
  W->>SHM: verify funds, debit/credit
  W->>SHM: append txn_log, increment txn_seq
  W->>SHM: unlock accounts
  W-->>C: TRANSFER_RESP(OK, new_balance, txn_id)
```

---

## Architecture

### Server: Multi-Process (Master-Worker / prefork)

- **Master process**
  - starts and manages workers (fork, monitor, restart)
  - handles SIGINT/SIGTERM (graceful shutdown)
  - exports metrics (connections, req/s, op counts, error counts, ...)

- **Worker processes**
  - handle client I/O: read frame → parse → handle → response
  - share chat/trading state via **shared memory**
  - enforce the locking strategy for trading operations

> On Linux, connection distribution can use `SO_REUSEPORT` so each worker can `accept()` independently, avoiding “master dispatching fds” complexity.

### IPC: Shared Memory

Shared memory should include:

- **Global metrics**: `total_requests`, `total_connections`, `op_counts[opcode]`, error counts
- **Users**: `user_id <-> username`, online/offline
- **Chat rooms**: member set, room event ring buffer (cross-worker broadcast)
- **Ledger**: `balance[user_id]`, `txn_seq`, `txn_log` (ring buffer for auditing)

### Concurrency & consistency

Consistency goals:

- **Atomicity**: debit+credit for TRANSFER succeeds together or fails together
- **Isolation**: concurrent transactions are equivalent to some serial order
- **Consistency**: balances never change incorrectly due to races (support asset-conservation checks)

Recommended locking:

- **One lock per account**: `account_lock[user_id]`
- **TRANSFER** locks two accounts with fixed order: `min(from,to)` then `max(from,to)`
- `txn_log` can use `txn_lock` or head/tail locks for ring buffer

Linux API suggestions:

- shared memory: `shm_open` + `ftruncate` + `mmap`
- inter-process sync:
  - POSIX semaphores: `sem_open/sem_wait/sem_post`
  - or `pthread_mutex` in shared memory with `PTHREAD_PROCESS_SHARED` (advanced)

---

## Custom Protocol Spec

### Frame header (recommended 32 bytes, network byte order / big-endian)

- `magic` (2) = 0x4E53 ("NS")
- `version` (1) = 1
- `flags` (1) = bit0: encrypted, bit1: compressed(optional), bit2: is_response
- `header_len` (2) = 32
- `body_len` (4)
- `opcode` (2)
- `status` (2) = 0 success; non-zero error code (response only)
- `req_id` (8) = client incrementing id (correlate responses / measure latency)
- `checksum` (4) = CRC32/Adler32(header_without_checksum + body)
- `reserved` (6) = 0

Body is defined per opcode (recommend length-prefixed strings: `u16 len + bytes`).

### OpCodes

Auth/connection:

- `0x0001 HELLO`
- `0x0002 LOGIN`
- `0x0003 LOGOUT`
- `0x0004 HEARTBEAT`

Chat:

- `0x0101 JOIN_ROOM`
- `0x0102 LEAVE_ROOM`
- `0x0103 CHAT_SEND`
- `0x0104 CHAT_BROADCAST` (server push)

Trading:

- `0x0201 DEPOSIT`
- `0x0202 WITHDRAW`
- `0x0203 TRANSFER`
- `0x0204 BALANCE`
- `0x0205 TXN_HISTORY` (optional)

### Status / error codes (examples)

- `0x0000 OK`
- `0x0001 ERR_BAD_PACKET`
- `0x0002 ERR_CHECKSUM_FAIL`
- `0x0003 ERR_UNAUTHORIZED`
- `0x0004 ERR_NOT_FOUND`
- `0x0005 ERR_INSUFFICIENT_FUNDS`
- `0x0006 ERR_SERVER_BUSY`
- `0x0007 ERR_TIMEOUT`

---

## Security & Reliability

### Security (at least 1; recommended 2)

- **Integrity (required)**: checksum (CRC32/Adler32)
- **Authentication (recommended)**: login handshake (nonce + simple hash/XOR demo)
- (Optional) **Encryption**: when `flags.encrypted=1`, encrypt body via XOR / AES-CTR

### Reliability (recommended 3)

- **Heartbeat/keep-alive**: detect disconnects and clean up sessions
- **Timeouts**: read/write timeout; on busy return `ERR_SERVER_BUSY`; client exponential backoff
- **Graceful shutdown**: SIGINT/SIGTERM releases shared memory/semaphores and exits safely

---

## Real Test (A++ required)

### Stress configuration (multi-threaded client)

- concurrent connections: ≥ 100 (also test 200)
- workload mix: chat-heavy / trade-heavy / mixed
- metrics: **p50/p95/p99 latency**, **throughput (req/s)**, error rate

### Suggested test matrix (30–60s each)

1. 100 conn / mixed
2. 200 conn / trade-heavy (lock contention)
3. payload size sweep: 32B → 256B → 1KB
4. worker scaling: N=1/2/4/8

### Output format (no Python)

- client output: console summary + CSV
- plots: `gnuplot` (or aggregate with `awk/sed`)

### Real Test runner (Linux)

Run the full matrix and generate plots (no Python):

```bash
bash scripts/run_real_tests.sh
gnuplot -c scripts/plot_latency.gp results/runs.csv results/latency.png
gnuplot -c scripts/plot_throughput.gp results/runs.csv results/throughput.png
```

Outputs:

- `results/runs.csv` (aggregated metrics for each run)
- `results/server.log` (server logs for evidence/debugging)
- `results/latency.png`, `results/throughput.png` (plots)

---

## Auditing discussion (A++ required)

### Protocol / input auditing

- enforce a max `body_len` to prevent length-bomb/OOM
- frame reassembly for partial reads/writes
- checksum failures: drop + count + optional rate limiting
- state machine: reject trading/chat ops before login

### Concurrency auditing (trading correctness)

- deadlock avoidance: fixed lock order (min→max)
- invariants: asset conservation (sum of balances + deposits remains consistent)

### Fault injection (strong bonus)

- `kill -9` a worker: master restarts it; shared memory remains consistent
- disconnect/reconnect: heartbeat timeout triggers cleanup
- SIGINT: graceful shutdown; verify IPC cleanup

### Performance auditing

- explain p99 latency spikes in trade-heavy workloads (lock contention)
- improvements (pick one and show before/after):
  - per-account locks (avoid a global lock)
  - reduce txn_log lock granularity (striped locks / improved ring buffer)

---

## Modularity & Libraries (.a/.so required)

Shared components (used by both client and server) should be encapsulated as libraries:

- `libproto`: frame encode/decode, checksum, opcode definitions
- `libnet`: socket wrappers, `readn/writen`, timeouts
- `liblog`: structured logging (pid, req_id, opcode, status)

---

## Build & Run

> This README shows target command formats. The actual commands should match your `Makefile` / `CMakeLists.txt`.

### Build (example)

```bash
make
```

### Run server (example)

```bash
./bin/server --port 9000 --workers 4 --shm /ns_trading_chat
```

### Run stress client (example)

```bash
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 60 --mix mixed --out results/results.csv
```

---

## Runtime Screenshots (required evidence)

Put screenshots under `docs/screenshots/` (suggested filenames):

- `server_start.png`
- `client_stress.png`
- `metrics.png`
- `graceful_shutdown.png`

---

## Team Roles (Individual Contribution)

- **mlgzackfly**
  - Server architecture & IPC:
    - Master/worker multi-process server (`bin/server`)，worker 管理、重啟與訊號處理
    - Shared memory 設計與初始化（ledger、chat rooms、metrics 等）
    - Cross-process synchronization（process-shared mutexes、metrics 統計）
  - Trading system:
    - Ledger data structure、per-account locks
    - TRANSFER atomicity + deadlock avoidance（固定鎖順序）
    - Asset conservation invariant 檢查與相關 auditing 設計

- **kristy**
  - Chat system:
    - Room management：join/leave、一致性的 room membership
    - Broadcast design：shared-memory ring buffer + worker push（cross-worker broadcast）
    - Heartbeat / online status management
  - Documentation & evidence:
    - `README.md`、`USAGE_ZH.md`、部分 `AUDITING.md` 內容整理
    - 截圖與證據說明：`docs/screenshots/README.md` 及實際截圖規劃

- **guan4tou2**
  - Client & stress testing:
    - Multi-threaded client (`bin/client`)：connections/threads/mix/payload-size/`--encrypt` 等參數
    - Latency/throughput/error metrics 收集，CSV 輸出與欄位設計
    - XOR encryption client 端流程實作與驗證
  - Testing & tooling:
    - 測試腳本：`scripts/run_real_tests.sh`、`scripts/test_system.sh`、`scripts/demo_all_features.sh`
    - `bin/metrics`：讀取 shared memory metrics 的小工具
    - 系統測試與結果檢查（含 Real Test matrix 執行與結果整理）

---

## References

- A++ spec draft: `PROJECT_A++_SPEC.md`
- Original requirement summary: `FINAL_PROJECT.md`

---

## A++ Done Criteria Checklist (Collaboration + Deliverables)

Use this as the final “definition of done” before submission. Every checked item should be **verifiable** (command output, file artifacts, screenshots, or logs).

### 1) Repo & collaboration (must)

- [x] **GitHub**: repository is pushed to GitHub and accessible to the instructor/TA
- [x] **Branch**: default branch is `main`
- [x] **Conventional commits (English)**: commit messages follow Conventional Commits (e.g., `feat: ...`, `fix: ...`, `docs: ...`)
- [x] **Roles**: the “Team Roles” section is accurate and each member owns at least one real module (not just a bullet point)
- [x] **Reproducibility**: a fresh machine can build and run using only README instructions (no hidden steps)

### 2) Build system (hard requirement)

- [x] **Build file exists**: `Makefile` (or `CMakeLists.txt`) is present at repo root
- [x] **One-command build**: `make` (or `cmake --build ...`) produces both `server` and `client`
- [x] **Clean build**: `make clean && make` works repeatedly
- [x] **No forbidden dependencies**: no HTTP/WebSocket libraries for application protocol (explicitly documented)

### 3) Libraries / modularity (.a/.so shared by client & server)

- [x] **Shared libs implemented** (at least 2–3): `libproto`, `libnet`, `liblog`
- [x] **Artifacts exist**: build produces `.a` and/or `.so` files (e.g., `libproto.a`)
- [x] **Actually used**: both `server` and `client` link against the shared libraries (not duplicated code)
- [x] **API boundary**: protocol encode/decode + checksum are inside `libproto` (not scattered)

### 4) Custom application-layer protocol (hard requirement)

- [x] **Not HTTP/WebSocket**: traffic is your own binary frame format
- [x] **Header/body spec**: header fields, sizes, endianness, and body formats are written in README/spec
- [x] **Frame correctness**: handles partial read/write (frame reassembly) and invalid frames safely
- [x] **Error handling**: server returns meaningful `status` codes (e.g., `ERR_BAD_PACKET`, `ERR_UNAUTHORIZED`)

### 5) Server: multi-process + IPC (hard requirement)

- [x] **Multi-process**: server runs with multiple worker processes (proof: logs show multiple PIDs)
- [x] **Shared memory IPC**: uses `shm_open + mmap` (or SysV shm) for shared state
- [x] **Cross-process synchronization**: uses POSIX semaphores or process-shared mutexes correctly
- [x] **Metrics in shared state**: total requests, per-opcode counts, error counts are tracked across workers

### 6) Trading consistency (ACID-style expectations)

- [x] **Per-account locking**: balances are protected by per-account locks (not a single global lock)
- [x] **Deadlock avoidance**: TRANSFER locks accounts in fixed order (min→max)
- [x] **Insufficient funds**: WITHDRAW/TRANSFER rejects correctly and never produces negative balance (if that’s your rule)
- [x] **Invariant check (auditing)**: asset conservation check is implemented and demonstrated in results/logs

### 7) Chat correctness under multi-process

- [x] **Room membership**: join/leave updates are consistent across workers
- [x] **Broadcast works across workers**: clients connected to different workers still receive room messages
- [x] **Delivery evidence**: a demo script / screenshot proves cross-worker broadcast correctness

### 8) Client: high concurrency stress testing (hard requirement)

- [x] **Multi-threaded client**: configurable threads and connections
- [x] **≥100 concurrent connections**: demonstrated with a real run (screenshot + logs)
- [x] **Workload mixes**: at least `trade-heavy` and `mixed` are supported

### 9) Security (choose ≥1; A++ recommends ≥2)

- [x] **Integrity**: checksum (CRC32/Adler32) is validated; failures are counted and rejected
- [x] **Authentication**: login handshake exists and is enforced (trading/chat ops rejected before login)
- [x] (Optional) **Encryption**: payload encryption implemented and documented (flags-driven) — **XOR demo only（教學示範，非生產強加密）**；可用 `--encrypt` 啟用

### 10) Reliability (choose ≥1; A++ recommends 3)

- [x] **Heartbeat**: detects dead connections; cleans up sessions
- [x] **Timeouts**: socket read/write timeouts and busy handling (`ERR_SERVER_BUSY` + client backoff)
- [x] **Graceful shutdown**: SIGINT/SIGTERM shuts down cleanly and releases shared memory/semaphores

### 11) Real Test (A++ “plus” requirement)

- [x] **Metrics output**: latency (p50/p95/p99), throughput (req/s), error rate
- [x] **Test matrix completed** (each 30–60s):
  - [x] 100 connections, mixed workload
  - [x] 200 connections, trade-heavy workload
  - [x] payload sweep (e.g., 32B → 256B → 1KB)
  - [x] worker scaling (e.g., 1/2/4/8 workers)
- [x] **Artifacts saved**: raw CSV results committed (or attached) + plots generated via `gnuplot`

### 12) Auditing discussion (A++ “plus” requirement)

- [x] **Protocol auditing**: max body length, checksum failures, invalid opcode/state machine behavior documented
- [x] **Concurrency auditing**: deadlock prevention explanation + invariant results (before/after if improved)
- [x] **Fault injection**:
  - [x] kill a worker (`kill -9`) and show master recovery + continued service
  - [x] disconnect/reconnect behavior validated (heartbeat cleanup)
  - [x] graceful shutdown validated (SIGINT) with resource cleanup proof
- [x] **Performance auditing**: identify bottleneck (e.g., lock contention) and show at least one improvement with before/after numbers

### 13) Evidence (screenshots/logs)

- [x] Screenshots saved under `docs/screenshots/`:
  - [x] `server_start.png` (shows workers/PIDs)
  - [x] `client_stress.png` (≥100 connections)
  - [x] `metrics.png` (p95/p99 + req/s) — 可由 `results/latency.png`、`results/throughput.png` 圖表或額外截圖提供證據
  - [x] `graceful_shutdown.png` (SIGINT + clean exit)
- [x] Logs include: pid, opcode, req_id, status, and error counts for debugging/auditing


