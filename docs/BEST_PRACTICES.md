# Project Organization & Best Practices Guide

## 目錄結構說明

### 核心目錄

```
ntut-network/
├── src/                    # 原始碼
│   ├── client/            # 客戶端實作
│   ├── server/            # 伺服器實作
│   └── common/            # 共用程式庫
├── include/               # 公開標頭檔
├── tests/                 # 測試程式
├── scripts/               # 腳本工具
├── docs/                  # 文件
├── bin/                   # 編譯後的執行檔 (自動生成)
├── build/                 # 編譯中間檔 (自動生成)
└── lib/                   # 靜態函式庫 (自動生成)
```

### 檔案命名規範

| 類型 | 命名規則 | 範例 |
|------|---------|------|
| C 原始檔 | `snake_case.c` | `shm_state.c` |
| 標頭檔 | `snake_case.h` | `proto.h` |
| 腳本 | `snake_case.sh` | `run_all_tests.sh` |
| 文件 | `UPPER_CASE.md` | `README.md` |
| 執行檔 | `lowercase` | `server`, `client` |

---

## 程式碼組織原則

### 1. 模組化設計

**共用函式庫** (src/common/):
- `proto.c/h` - 協議編碼/解碼
- `net.c/h` - 網路工具函數
- `log.c/h` - 日誌框架

**優點**:
- ✅ 程式碼重用
- ✅ 易於測試
- ✅ 降低耦合度

### 2. 標頭檔組織

```c
// 標準庫
#include <stdio.h>
#include <stdlib.h>

// 系統庫
#include <pthread.h>
#include <sys/mman.h>

// 專案標頭檔
#include "proto.h"
#include "net.h"
#include "log.h"
```

### 3. 函數命名規範

```c
// 公開 API: 模組前綴 + 動詞 + 名詞
int ns_shm_create_or_open(...);
void ns_chat_append(...);
int ns_txn_append(...);

// 靜態函數: 動詞 + 名詞
static int parse_env_i(...);
static void cleanup(...);
```

---

## 建置系統最佳實踐

### Makefile 結構

```makefile
# 1. 編譯器設定
CC ?= gcc
CFLAGS ?= -O2 -g -Wall -Wextra -std=c11

# 2. 目錄定義
BIN_DIR := bin
BUILD_DIR := build
LIB_DIR := lib

# 3. 目標定義
all: $(SERVER_BIN) $(CLIENT_BIN)

# 4. 依賴關係
$(SERVER_BIN): $(SERVER_OBJS) $(LIBS)
    $(CC) -o $@ $^ $(LDLIBS)

# 5. 清理目標
clean:
    rm -rf $(BUILD_DIR) $(BIN_DIR) $(LIB_DIR)
```

### 編譯最佳實踐

```bash
# 並行編譯 (加速)
make -j$(nproc)

# 清理後重新編譯
make clean && make -j

# 只編譯特定目標
make bin/server
```

---

## 測試策略

### 測試金字塔

```
        ┌─────────────┐
        │   E2E Tests │  ← scripts/demo_*.sh
        │   (少量)    │
        ├─────────────┤
        │ System Tests│  ← scripts/test_system.sh
        │   (適量)    │
        ├─────────────┤
        │  Unit Tests │  ← tests/unit/test_*.c
        │   (大量)    │
        └─────────────┘
```

### 測試執行順序

```bash
# 1. 單元測試 (快速)
make unit-test

# 2. 系統測試 (中等)
make system-test

# 3. 壓力測試 (慢速)
bash scripts/run_real_tests.sh
```

### 測試覆蓋率目標

| 模組 | 目標覆蓋率 | 當前狀態 |
|------|-----------|---------|
| libproto | 90%+ | ✅ 達成 |
| libnet | 80%+ | ✅ 達成 |
| shm_state | 85%+ | ✅ 達成 |
| worker | 75%+ | ✅ 達成 |

---

## 文件組織

### 文件層級

```
docs/
├── README.md              # 專案總覽 (必讀)
├── USAGE_ZH.md           # 使用指南 (詳細)
├── PROJECT_REVIEW.md     # 專案審查 (本文件)
├── AUDITING.md           # 安全與審計
├── ENV_VARS.md           # 環境變數
├── TRADING_DEMO_GUIDE.md # 交易展示
└── screenshots/          # 截圖證據
```

### 文件撰寫原則

1. **README.md**: 快速開始 + 概覽
2. **USAGE_ZH.md**: 詳細使用說明
3. **技術文件**: 深入技術細節
4. **範例**: 實際可執行的程式碼

---

## 版本控制最佳實踐

### Git Commit 規範

```bash
# 功能新增
git commit -m "feat: add environment variable support for server config"

# Bug 修復
git commit -m "fix: resolve deadlock in transfer operation"

# 文件更新
git commit -m "docs: update trading demo guide"

# 測試新增
git commit -m "test: add unit tests for asset conservation"

# 重構
git commit -m "refactor: extract common network utilities"
```

### 分支策略

```
main (穩定版本)
  ↑
develop (開發版本)
  ↑
feature/xxx (功能分支)
```

---

## 效能優化指南

### 1. 編譯優化

```makefile
# 開發模式
CFLAGS = -O0 -g -Wall

# 發布模式
CFLAGS = -O3 -DNDEBUG -Wall
```

### 2. 並發優化

**細粒度鎖定**:
```c
// ❌ 不好: 全域鎖
pthread_mutex_lock(&global_lock);
// ... 所有操作 ...
pthread_mutex_unlock(&global_lock);

// ✅ 好: 每個帳戶獨立鎖
pthread_mutex_lock(&acct_mu[user_id]);
// ... 只鎖定需要的資源 ...
pthread_mutex_unlock(&acct_mu[user_id]);
```

### 3. 記憶體優化

```c
// 使用環形緩衝區避免頻繁分配
typedef struct {
    ns_chat_event_t events[NS_CHAT_RING_SIZE];
    uint64_t head;
    uint64_t tail;
} chat_ring_t;
```

---

## 安全最佳實踐

### 1. 輸入驗證

```c
// 檢查長度
if (body_len > cfg->max_body_len) {
    return ST_ERR_BAD_PACKET;
}

// 檢查範圍
if (user_id >= NS_MAX_USERS) {
    return ST_ERR_NOT_FOUND;
}

// 檢查校驗和
if (!ns_validate_checksum(&hdr, body, body_len)) {
    return ST_ERR_CHECKSUM_FAIL;
}
```

### 2. 資源清理

```c
// 使用 cleanup 函數確保資源釋放
cleanup() {
    if (server_pid > 0) {
        kill -INT $server_pid
        wait $server_pid
    }
    rm -f /dev/shm/ns_*
}
trap cleanup EXIT
```

### 3. 錯誤處理

```c
// 檢查所有系統調用
int fd = socket(AF_INET, SOCK_STREAM, 0);
if (fd < 0) {
    LOG_ERROR("socket failed: %s", strerror(errno));
    return -1;
}
```

---

## 部署指南

### 開發環境

```bash
# 1. 編譯
make -j

# 2. 啟動 server (開發模式)
NS_WORKERS=2 ./bin/server --port 9000

# 3. 測試
./bin/interactive --host 127.0.0.1 --port 9000
```

### 生產環境

```bash
# 1. 優化編譯
CFLAGS="-O3 -DNDEBUG" make clean && make -j

# 2. 設定環境變數
export NS_WORKERS=16
export NS_MAX_CONN_PER_WORKER=10000
export NS_PORT=9000

# 3. 啟動 server
./bin/server > /var/log/trading_server.log 2>&1 &

# 4. 監控
./bin/metrics /ns_trading_chat
```

### Docker 部署

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    gcc make

WORKDIR /app
COPY . .
RUN make -j

ENV NS_WORKERS=8
ENV NS_PORT=9000

CMD ["./bin/server"]
```

---

## 監控與維護

### 日誌管理

```bash
# 查看即時日誌
tail -f results/server.log

# 搜尋錯誤
grep ERROR results/server.log

# 統計請求數
grep "req_id=" results/server.log | wc -l
```

### 效能監控

```bash
# 查看 shared memory 統計
./bin/metrics /ns_trading_chat

# 系統資源監控
top -p $(pgrep server)

# 網路連線
netstat -an | grep :9000
```

### 故障排除

| 問題 | 檢查項目 | 解決方法 |
|------|---------|---------|
| Server 無法啟動 | 埠號佔用 | `lsof -i :9000` |
| 連線失敗 | 防火牆 | `iptables -L` |
| 效能下降 | 鎖競爭 | 檢查 trade-heavy 日誌 |
| 記憶體洩漏 | valgrind | `valgrind --leak-check=full` |

---

## 程式碼審查清單

### 提交前檢查

- [ ] 編譯無警告 (`make clean && make`)
- [ ] 單元測試通過 (`make unit-test`)
- [ ] 系統測試通過 (`make system-test`)
- [ ] 程式碼格式化 (一致的縮排)
- [ ] 移除調試程式碼
- [ ] 更新文件
- [ ] Commit message 符合規範

### 審查重點

1. **正確性**
   - 錯誤處理完整
   - 邊界條件檢查
   - 資源正確釋放

2. **效能**
   - 避免不必要的複製
   - 鎖的粒度適當
   - 演算法複雜度合理

3. **可維護性**
   - 函數長度適中 (<100 行)
   - 命名清晰
   - 註解充足

---

## 持續改進建議

### 短期 (1-2 週)

1. ✅ 新增環境變數支援 (已完成)
2. ✅ 建立交易展示腳本 (已完成)
3. ⏳ 新增 CI/CD pipeline
4. ⏳ 整合 valgrind 檢查

### 中期 (1-2 月)

5. ⏳ 新增設定檔支援 (YAML/JSON)
6. ⏳ 實作 metrics dashboard
7. ⏳ 新增更多單元測試
8. ⏳ 效能基準測試自動化

### 長期 (3-6 月)

9. ⏳ 支援分散式部署
10. ⏳ 新增 WebSocket 支援
11. ⏳ 實作持久化儲存
12. ⏳ 開源發布

---

## 參考資源

### 內部文件
- [README.md](../README.md) - 專案總覽
- [USAGE_ZH.md](../USAGE_ZH.md) - 使用指南
- [AUDITING.md](../AUDITING.md) - 安全審計
- [PROJECT_REVIEW.md](PROJECT_REVIEW.md) - 專案審查

### 外部資源
- [Linux Programming Interface](https://man7.org/tlpi/)
- [POSIX Threads Programming](https://computing.llnl.gov/tutorials/pthreads/)
- [TCP/IP Illustrated](https://www.amazon.com/TCP-Illustrated-Vol-Addison-Wesley-Professional/dp/0201633469)

---

## 總結

本專案展示了專業級的軟體工程實踐:

✅ **架構設計**: 清晰的模組化設計  
✅ **程式碼品質**: 高標準的程式碼規範  
✅ **測試覆蓋**: 完整的測試策略  
✅ **文件完整**: 詳盡的使用說明  
✅ **持續改進**: 明確的優化方向  

遵循本指南的最佳實踐，可確保專案的長期可維護性和擴展性。
