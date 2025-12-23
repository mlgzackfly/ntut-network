# 環境變數設定指南

本文件說明如何使用環境變數來快速調整 server 設定，無需修改程式碼或重新編譯。

## 支援的環境變數

| 環境變數 | 說明 | 預設值 | 範圍 |
|---------|------|--------|------|
| `NS_BIND_IP` | 綁定的 IP 位址 | `0.0.0.0` (所有介面) | 任何有效 IP |
| `NS_PORT` | 監聽埠號 | `9000` | 1-65535 |
| `NS_WORKERS` | Worker 進程數量 | `4` | 1-1024 |
| `NS_SHM_NAME` | Shared memory 名稱 | `/ns_trading_chat` | 任何有效路徑 |
| `NS_MAX_BODY_LEN` | 訊息主體最大長度 (bytes) | `65536` | 1024-1048576 |
| `NS_MAX_CONN_PER_WORKER` | 每個 worker 最大連線數 | `1000` | 1-100000 |
| `NS_RECV_TIMEOUT_MS` | 接收逾時 (毫秒) | `30000` | 100-3600000 |
| `NS_SEND_TIMEOUT_MS` | 傳送逾時 (毫秒) | `30000` | 100-3600000 |

## 優先順序

設定的優先順序（由高到低）：
1. **命令列參數** - 最高優先權
2. **環境變數** - 覆寫預設值
3. **程式碼預設值** - 最低優先權

## 使用範例

### 範例 1: 基本使用
```bash
# 使用 8 個 workers 和 8080 埠啟動
NS_WORKERS=8 NS_PORT=8080 ./bin/server
```

### 範例 2: 高並發設定
```bash
# 高並發環境：更多 workers 和更大的連線限制
NS_WORKERS=16 \
NS_MAX_CONN_PER_WORKER=5000 \
NS_RECV_TIMEOUT_MS=60000 \
NS_SEND_TIMEOUT_MS=60000 \
./bin/server
```

### 範例 3: 測試環境
```bash
# 測試環境：使用不同的 shared memory 名稱避免衝突
NS_SHM_NAME=/ns_test_instance \
NS_PORT=9001 \
./bin/server
```

### 範例 4: 低延遲設定
```bash
# 低延遲優化：減少 timeout 時間
NS_RECV_TIMEOUT_MS=5000 \
NS_SEND_TIMEOUT_MS=5000 \
NS_WORKERS=8 \
./bin/server
```

### 範例 5: 大訊息支援
```bash
# 支援較大的訊息
NS_MAX_BODY_LEN=262144 \
./bin/server
```

### 範例 6: 環境變數 + 命令列參數混用
```bash
# 環境變數設定預設值，命令列參數覆寫
NS_WORKERS=8 NS_PORT=8080 ./bin/server --port 9000
# 實際使用: port=9000 (命令列覆寫), workers=8 (環境變數)
```

## 在腳本中使用

### 開發環境腳本
```bash
#!/bin/bash
# dev_server.sh - 開發環境設定

export NS_WORKERS=2
export NS_PORT=9000
export NS_SHM_NAME=/ns_dev
export NS_RECV_TIMEOUT_MS=60000

./bin/server
```

### 生產環境腳本
```bash
#!/bin/bash
# prod_server.sh - 生產環境設定

export NS_WORKERS=16
export NS_PORT=9000
export NS_SHM_NAME=/ns_prod
export NS_MAX_CONN_PER_WORKER=10000
export NS_RECV_TIMEOUT_MS=30000
export NS_SEND_TIMEOUT_MS=30000

./bin/server
```

## Docker 環境

在 Docker 中使用環境變數：

```dockerfile
# Dockerfile
FROM ubuntu:22.04
# ... 其他設定 ...

ENV NS_WORKERS=8
ENV NS_PORT=9000
ENV NS_MAX_CONN_PER_WORKER=5000

CMD ["./bin/server"]
```

或使用 docker-compose.yml：

```yaml
version: '3'
services:
  trading_server:
    build: .
    environment:
      - NS_WORKERS=8
      - NS_PORT=9000
      - NS_MAX_CONN_PER_WORKER=5000
    ports:
      - "9000:9000"
```

## 驗證設定

啟動 server 後，檢查日誌確認設定是否正確套用：

```bash
# 啟動 server
NS_WORKERS=8 NS_PORT=8080 ./bin/server

# 日誌應顯示：
# Server starting: port=8080 workers=8 shm=/ns_trading_chat
```

## 測試環境變數功能

執行測試腳本驗證環境變數功能：

```bash
bash scripts/test_env_vars.sh
```

## 常見使用場景

### 1. 快速效能調校
不需要重新編譯，直接調整 workers 數量測試效能：
```bash
for workers in 2 4 8 16; do
  echo "Testing with $workers workers..."
  NS_WORKERS=$workers ./bin/server &
  # 執行測試...
  killall server
done
```

### 2. 多實例部署
在同一台機器上執行多個 server 實例：
```bash
# Instance 1
NS_PORT=9001 NS_SHM_NAME=/ns_instance1 ./bin/server &

# Instance 2
NS_PORT=9002 NS_SHM_NAME=/ns_instance2 ./bin/server &
```

### 3. CI/CD 整合
在 CI/CD pipeline 中使用環境變數：
```bash
# .gitlab-ci.yml 或 .github/workflows/test.yml
NS_WORKERS=4 NS_PORT=9999 NS_SHM_NAME=/ns_ci_test ./bin/server &
# 執行測試...
```

## 注意事項

1. **範圍檢查**: 環境變數值會進行範圍檢查，超出範圍會使用預設值
2. **型別檢查**: 無效的值（如非數字）會被忽略並使用預設值
3. **Shared Memory**: 修改 `NS_SHM_NAME` 時，確保不同實例使用不同名稱
4. **Port 衝突**: 確保 `NS_PORT` 沒有被其他程式佔用

## 查看說明

執行以下命令查看完整的環境變數說明：

```bash
./bin/server --help
```
