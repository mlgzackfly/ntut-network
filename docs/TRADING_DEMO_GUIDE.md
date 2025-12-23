# Trading Demo Scripts - 使用指南

本目錄包含兩個交易系統展示腳本，用於展示所有交易功能。

## 腳本說明

### 1. demo_trading.sh - 自動化展示腳本

**用途**: 自動執行一系列交易操作，展示所有功能

**執行方式**:
```bash
bash scripts/demo_trading.sh
```

**展示內容**:
1. ✅ 使用者登入與認證
2. ✅ 查詢餘額 (BALANCE)
3. ✅ 存款操作 (DEPOSIT)
4. ✅ 提款操作 (WITHDRAW)
5. ✅ 轉帳操作 (TRANSFER)
6. ✅ 餘額不足錯誤處理
7. ✅ 多使用者並發操作

**輸出範例**:
```
==========================================
    Trading System Demo
==========================================

[1/7] Starting server...
✓ Server started (PID: 1234)

[2/7] User A - Initial Balance Check
----------------------------------------
Login successful! User ID: 969, Balance: 100000
Balance: 100000
✓ User A initial balance: 100000

[3/7] User A - Deposit Operation
----------------------------------------
Command: deposit 50000
Deposit successful! New balance: 150000
✓ Deposit completed

[4/7] User A - Withdraw Operation
----------------------------------------
Command: withdraw 20000
Withdraw successful! New balance: 130000
✓ Withdraw completed

[5/7] User B - Login and Check Balance
----------------------------------------
Login successful! User ID: 784, Balance: 100000
✓ User B logged in

[6/7] Transfer from User A to User B
----------------------------------------
User B ID: 784
Command: transfer 784 30000
Transfer successful! New balance: 100000
✓ Transfer completed

[7/7] Verify User B Received Transfer
----------------------------------------
Balance: 130000
✓ Verification completed

==========================================
Bonus: Testing Error Handling
==========================================

Test 1: Insufficient Funds
----------------------------------------
Insufficient funds

Test 2: Multiple Operations in Sequence
----------------------------------------
Deposit successful! New balance: 110000
Withdraw successful! New balance: 105000
Balance: 105000
```

**特點**:
- 🚀 一鍵執行，無需手動輸入
- 📊 清晰的步驟說明和結果展示
- 🎨 彩色輸出，易於閱讀
- ✅ 包含錯誤處理測試
- 📝 自動產生 server log

---

### 2. demo_trading_interactive.sh - 互動式展示腳本

**用途**: 提供互動式介面，讓使用者手動執行交易操作

**執行方式**:
```bash
bash scripts/demo_trading_interactive.sh
```

**互動流程**:
1. 輸入使用者名稱
2. 自動連線到 server
3. 使用命令執行交易操作

**可用命令**:
- `balance` - 查詢餘額
- `deposit <金額>` - 存款
- `withdraw <金額>` - 提款
- `transfer <使用者ID> <金額>` - 轉帳
- `join <房間ID>` - 加入聊天室
- `chat <訊息>` - 發送訊息
- `leave` - 離開聊天室
- `quit` - 退出

**使用範例**:
```bash
# 終端 1
bash scripts/demo_trading_interactive.sh
# 輸入使用者名稱: Alice

# 終端 2
bash scripts/demo_trading_interactive.sh
# 輸入使用者名稱: Bob

# 在 Alice 的終端執行:
> balance
Balance: 100000

> deposit 50000
Deposit successful! New balance: 150000

> transfer 784 30000  # 784 是 Bob 的 user_id
Transfer successful! New balance: 120000

# 在 Bob 的終端執行:
> balance
Balance: 130000  # 收到了 Alice 的轉帳
```

**特點**:
- 🎮 互動式操作，適合 Demo 展示
- 👥 支援多使用者同時連線
- 💬 可以測試聊天功能
- 🎨 美觀的 UI 介面
- 📚 內建使用說明

---

## 設定說明

### 環境變數

兩個腳本都支援環境變數設定：

```bash
# 自訂埠號
PORT=8080 bash scripts/demo_trading.sh

# 自訂 shared memory 名稱
SHM_NAME=/ns_my_demo bash scripts/demo_trading.sh
```

### 預設設定

| 腳本 | 預設埠號 | Shared Memory |
|------|---------|---------------|
| demo_trading.sh | 9001 | /ns_trading_demo |
| demo_trading_interactive.sh | 9002 | /ns_trading_interactive |

---

## 測試場景

### 場景 1: 基本交易流程
```bash
bash scripts/demo_trading.sh
```
展示完整的交易流程，包含所有操作類型。

### 場景 2: 多使用者轉帳
開啟兩個終端：
```bash
# 終端 1
bash scripts/demo_trading_interactive.sh
# 使用者名稱: Alice

# 終端 2
bash scripts/demo_trading_interactive.sh
# 使用者名稱: Bob
```

在 Alice 終端執行轉帳給 Bob，然後在 Bob 終端查詢餘額。

### 場景 3: 錯誤處理測試
在互動式腳本中測試：
```bash
> withdraw 999999999
Insufficient funds

> transfer 99999 1000
Failed to transfer: status=4  # 使用者不存在
```

---

## 查看詳細資訊

### Server 日誌
```bash
# demo_trading.sh 的日誌
cat results/trading_demo_server.log

# demo_trading_interactive.sh 的日誌
cat /tmp/trading_interactive_server.log
```

### Shared Memory 統計
```bash
# 查看 demo_trading.sh 的統計
./bin/metrics /ns_trading_demo

# 查看 demo_trading_interactive.sh 的統計
./bin/metrics /ns_trading_interactive
```

---

## 故障排除

### 問題 1: 埠號被佔用
```
ERROR: Address already in use
```

**解決方法**:
```bash
# 使用不同的埠號
PORT=9999 bash scripts/demo_trading.sh
```

### 問題 2: Server 啟動失敗
```
Failed to start server
```

**解決方法**:
1. 確認已編譯: `make -j`
2. 檢查 server log: `cat results/trading_demo_server.log`
3. 清理舊的 shared memory: `rm -f /dev/shm/ns_trading_*`

### 問題 3: 連線逾時
```
Failed to connect
```

**解決方法**:
1. 確認 server 正在執行: `ps aux | grep server`
2. 檢查防火牆設定
3. 確認埠號正確

---

## 進階使用

### 整合到測試流程
```bash
# 在 CI/CD 中執行
bash scripts/demo_trading.sh > trading_demo_output.txt 2>&1
if [ $? -eq 0 ]; then
    echo "Trading demo passed"
else
    echo "Trading demo failed"
    exit 1
fi
```

### 效能測試
```bash
# 使用壓測 client 進行交易密集測試
./bin/client --host 127.0.0.1 --port 9001 \
  --connections 100 --threads 16 --duration 30 \
  --mix trade-heavy --out results/trading_stress.csv
```

---

## 相關文件

- [README.md](../README.md) - 專案總覽
- [USAGE_ZH.md](../USAGE_ZH.md) - 完整使用說明
- [ENV_VARS.md](../docs/ENV_VARS.md) - 環境變數設定
- [AUDITING.md](../AUDITING.md) - 審計與測試

---

## 快速參考

### 一行命令執行所有測試
```bash
# 自動化展示
bash scripts/demo_trading.sh

# 互動式測試
bash scripts/demo_trading_interactive.sh

# 查看統計
./bin/metrics /ns_trading_demo
```

### 清理環境
```bash
# 停止所有 server
killall server

# 清理 shared memory
rm -f /dev/shm/ns_trading_*

# 清理日誌
rm -f results/trading_demo_*.log /tmp/trading_interactive_*.log
```
