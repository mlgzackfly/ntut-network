# 環境變數功能實作總結

## 完成項目

### 1. 程式碼修改
- ✅ 修改 `src/server/main.c`，新增完整的環境變數覆寫支援
- ✅ 支援 8 個環境變數設定：
  - `NS_BIND_IP` - 綁定 IP 位址
  - `NS_PORT` - 監聽埠號
  - `NS_WORKERS` - Worker 進程數量
  - `NS_SHM_NAME` - Shared memory 名稱
  - `NS_MAX_BODY_LEN` - 訊息主體最大長度
  - `NS_MAX_CONN_PER_WORKER` - 每個 worker 最大連線數
  - `NS_RECV_TIMEOUT_MS` - 接收逾時
  - `NS_SEND_TIMEOUT_MS` - 傳送逾時

### 2. 使用說明更新
- ✅ 更新 `--help` 輸出，包含完整的環境變數說明
- ✅ 建立詳細的使用文件 `docs/ENV_VARS.md`

### 3. 測試腳本
- ✅ `scripts/test_env_vars.sh` - 自動化測試腳本，驗證環境變數功能
- ✅ `scripts/demo_env_vars.sh` - 互動式示範腳本

### 4. 測試結果
所有測試通過 ✓
```
✓ NS_PORT=8888 applied
✓ NS_WORKERS=2 applied
✓ NS_SHM_NAME=/ns_test_env applied
```

## 使用範例

### 基本使用
```bash
# 使用 8 個 workers 和 8080 埠
NS_WORKERS=8 NS_PORT=8080 ./bin/server
```

### 高並發設定
```bash
NS_WORKERS=16 \
NS_MAX_CONN_PER_WORKER=5000 \
NS_RECV_TIMEOUT_MS=60000 \
./bin/server
```

### 測試環境
```bash
NS_SHM_NAME=/ns_test \
NS_PORT=9001 \
./bin/server
```

## 優先順序

設定的優先順序（由高到低）：
1. **命令列參數** - 最高優先權
2. **環境變數** - 覆寫預設值
3. **程式碼預設值** - 最低優先權

範例：
```bash
# port 最終為 9000（命令列覆寫環境變數）
NS_PORT=8080 ./bin/server --port 9000
```

## 驗證方法

### 1. 查看說明
```bash
./bin/server --help
```

### 2. 執行測試
```bash
bash scripts/test_env_vars.sh
```

### 3. 檢查日誌
啟動 server 後，檢查日誌確認設定：
```
Server starting: port=8080 workers=8 shm=/ns_trading_chat
```

## 檔案清單

| 檔案 | 說明 |
|------|------|
| `src/server/main.c` | 主程式（已修改） |
| `docs/ENV_VARS.md` | 環境變數使用指南 |
| `scripts/test_env_vars.sh` | 自動化測試腳本 |
| `scripts/demo_env_vars.sh` | 互動式示範腳本 |

## 優點

1. **無需重新編譯** - 修改設定不需要重新編譯程式
2. **快速測試** - 可以快速測試不同設定組合
3. **CI/CD 友善** - 容易整合到自動化流程
4. **多實例部署** - 方便在同一台機器上執行多個實例
5. **向後相容** - 不影響現有的命令列參數使用方式

## 注意事項

- 環境變數值會進行範圍檢查
- 無效的值會被忽略並使用預設值
- 修改 `NS_SHM_NAME` 時，確保不同實例使用不同名稱
- 確保 `NS_PORT` 沒有被其他程式佔用
