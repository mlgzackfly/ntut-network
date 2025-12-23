# Code Quality Tools Guide

本文件說明如何使用專案中的程式碼品質檢查工具。

## 可用工具

### 1. Memory Leak Detection (記憶體洩漏檢測)

使用 Valgrind 檢查記憶體洩漏問題。

**執行方式**:
```bash
# 使用 Makefile target
make check-memory

# 或直接執行腳本
bash scripts/check_memory.sh
```

**檢查項目**:
- Server 執行檔記憶體洩漏
- Unit tests 記憶體洩漏
- Metrics tool 記憶體洩漏

**輸出**:
- 報告檔案: `results/memory_check.txt`
- 詳細日誌: `results/valgrind_*.log`

**安裝 Valgrind**:
```bash
# Ubuntu/Debian
sudo apt-get install valgrind

# macOS (需要 Homebrew)
brew install valgrind
```

---

### 2. Static Analysis (靜態分析)

使用 cppcheck 和 clang-tidy 進行靜態程式碼分析。

**執行方式**:
```bash
# 使用 Makefile target
make check-static

# 或直接執行腳本
bash scripts/check_static.sh
```

**檢查項目**:
- 常見程式設計錯誤
- 記憶體管理問題
- 未使用的變數
- 潛在的 buffer overflow
- 程式碼風格問題

**輸出**:
- 報告檔案: `results/static_analysis.txt`

**安裝工具**:
```bash
# Ubuntu/Debian
sudo apt-get install cppcheck clang-tidy

# macOS
brew install cppcheck llvm
```

---

### 3. Combined Check (綜合檢查)

執行所有程式碼品質檢查。

**執行方式**:
```bash
make check
```

這會依序執行:
1. Static analysis (靜態分析)
2. Memory leak detection (記憶體洩漏檢測)

---

## 使用範例

### 開發流程中使用

```bash
# 1. 修改程式碼
vim src/server/worker.c

# 2. 編譯
make -j

# 3. 執行測試
make test

# 4. 執行程式碼品質檢查
make check

# 5. 查看報告
cat results/static_analysis.txt
cat results/memory_check.txt
```

### CI/CD 整合

```bash
#!/bin/bash
# 在 CI/CD pipeline 中使用

# 建置
make clean && make -j

# 測試
make test

# 程式碼品質檢查
make check-static || echo "Static analysis warnings found"
make check-memory || echo "Memory issues found"

# 檢查是否有嚴重錯誤
if grep -q "error:" results/static_analysis.txt; then
    echo "Static analysis errors found!"
    exit 1
fi
```

### 提交前檢查

```bash
# 建立 git pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "Running code quality checks..."
make check-static
if [ $? -ne 0 ]; then
    echo "Static analysis failed. Please fix issues before committing."
    exit 1
fi
EOF

chmod +x .git/hooks/pre-commit
```

---

## 工具說明

### Valgrind

**用途**: 記憶體洩漏檢測、記憶體錯誤檢測

**常見問題類型**:
- Memory leaks (記憶體洩漏)
- Invalid memory access (無效記憶體存取)
- Use of uninitialized values (使用未初始化的值)
- Double free (重複釋放)

**範例輸出**:
```
==12345== LEAK SUMMARY:
==12345==    definitely lost: 0 bytes in 0 blocks
==12345==    indirectly lost: 0 bytes in 0 blocks
==12345==      possibly lost: 0 bytes in 0 blocks
==12345==    still reachable: 0 bytes in 0 blocks
```

### cppcheck

**用途**: C/C++ 靜態分析

**檢查項目**:
- Null pointer dereference
- Buffer overflows
- Memory leaks
- Unused variables
- Division by zero

**範例輸出**:
```
[src/server/worker.c:123]: (warning) Variable 'x' is assigned a value that is never used
[src/common/net.c:45]: (error) Possible null pointer dereference: ptr
```

### clang-tidy

**用途**: 現代 C/C++ 最佳實踐檢查

**檢查項目**:
- Modernization suggestions
- Performance issues
- Readability improvements
- Bug-prone patterns

---

## 報告解讀

### Memory Check Report

```
=========================================
Memory Leak Detection Report
Date: 2025-12-23
=========================================

=== Server Memory Check ===
Server: definitely lost: 0 bytes in 0 blocks

=== Unit Tests Memory Check ===
test_proto: definitely lost: 0 bytes in 0 blocks
test_shm: definitely lost: 0 bytes in 0 blocks
```

**解讀**:
- `definitely lost: 0 bytes` - ✅ 沒有記憶體洩漏
- `definitely lost: X bytes` - ❌ 有記憶體洩漏，需要修復

### Static Analysis Report

```
=== cppcheck Analysis ===
Checking src/server/worker.c...
[src/server/worker.c:123]: (style) Variable 'x' can be const

=== clang-tidy Analysis ===
warning: use of undeclared identifier 'foo' [clang-diagnostic-error]
```

**解讀**:
- `(error)` - ❌ 嚴重錯誤，必須修復
- `(warning)` - ⚠️ 警告，建議修復
- `(style)` - 💡 風格建議，可選擇性修復

---

## 故障排除

### 問題 1: Valgrind 執行緩慢

**原因**: Valgrind 會大幅降低程式執行速度

**解決方法**:
- 減少測試時間 (修改腳本中的 timeout 值)
- 只檢查特定執行檔
- 在較快的機器上執行

### 問題 2: 太多誤報

**cppcheck 誤報**:
```bash
# 在程式碼中加入 suppression
// cppcheck-suppress unusedVariable
int x = 0;
```

**clang-tidy 誤報**:
```bash
# 修改 scripts/check_static.sh 中的 -checks 參數
-checks='*,-specific-check-to-disable'
```

### 問題 3: 工具未安裝

**症狀**: 腳本顯示工具未安裝訊息

**解決方法**:
1. 按照腳本提示安裝工具
2. 或跳過該檢查（腳本會自動處理）

---

## 最佳實踐

### 1. 定期執行

```bash
# 每週執行一次完整檢查
make check

# 每次提交前執行快速檢查
make check-static
```

### 2. 修復優先級

1. **高**: `error` 級別的問題
2. **中**: `warning` 級別的問題
3. **低**: `style` 級別的建議

### 3. 持續改進

- 追蹤問題數量趨勢
- 設定目標（例如：0 errors, <10 warnings）
- 定期更新工具版本

---

## 相關文件

- [BEST_PRACTICES.md](BEST_PRACTICES.md) - 專案最佳實踐
- [PROJECT_REVIEW.md](PROJECT_REVIEW.md) - 專案審查報告
- [README.md](../README.md) - 專案總覽

---

## 快速參考

```bash
# 記憶體檢查
make check-memory

# 靜態分析
make check-static

# 全部檢查
make check

# 查看報告
cat results/memory_check.txt
cat results/static_analysis.txt

# 查看詳細日誌
cat results/valgrind_server.log
```
