#!/usr/bin/env bash
# Memory Leak Detection Script using Valgrind
# 檢查 server 和 client 的記憶體洩漏問題

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RESULTS_DIR="$ROOT/results"
mkdir -p "$RESULTS_DIR"

REPORT_FILE="$RESULTS_DIR/memory_check.txt"

echo "=========================================="
echo "Memory Leak Detection (Valgrind)"
echo "=========================================="
echo ""

# 檢查 valgrind 是否安裝
if ! command -v valgrind &> /dev/null; then
    echo "⚠️  Valgrind not installed"
    echo ""
    echo "To install on Ubuntu/Debian:"
    echo "  sudo apt-get install valgrind"
    echo ""
    echo "To install on macOS:"
    echo "  brew install valgrind"
    echo ""
    exit 0
fi

echo "✓ Valgrind found: $(valgrind --version)"
echo ""

# 確保已編譯
if [ ! -f "./bin/server" ] || [ ! -f "./bin/client" ]; then
    echo "Building project..."
    make -s clean && make -s -j
fi

# 清空報告檔案
: > "$REPORT_FILE"

echo "=========================================" >> "$REPORT_FILE"
echo "Memory Leak Detection Report" >> "$REPORT_FILE"
echo "Date: $(date)" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 測試 1: 檢查 server (短時間執行)
echo "[1/3] Checking server memory leaks..."
echo "" >> "$REPORT_FILE"
echo "=== Server Memory Check ===" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 啟動 server 並在背景執行
timeout 3s valgrind \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --verbose \
    --log-file="$RESULTS_DIR/valgrind_server.log" \
    ./bin/server --port 9999 --workers 2 --shm /ns_valgrind_test \
    > /dev/null 2>&1 || true

# 清理 shared memory
rm -f /dev/shm/ns_valgrind_test 2>/dev/null || true

# 分析結果
if [ -f "$RESULTS_DIR/valgrind_server.log" ]; then
    LEAKS=$(grep "definitely lost" "$RESULTS_DIR/valgrind_server.log" | tail -1 || echo "0 bytes")
    echo "Server leak summary: $LEAKS"
    echo "Server: $LEAKS" >> "$REPORT_FILE"
    
    # 提取摘要
    grep -A 5 "LEAK SUMMARY" "$RESULTS_DIR/valgrind_server.log" >> "$REPORT_FILE" 2>/dev/null || true
else
    echo "Server: No valgrind log generated" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"

# 測試 2: 檢查 unit tests
echo "[2/3] Checking unit test memory leaks..."
echo "" >> "$REPORT_FILE"
echo "=== Unit Tests Memory Check ===" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ -f "./bin/test_proto" ]; then
    valgrind \
        --leak-check=full \
        --error-exitcode=1 \
        --log-file="$RESULTS_DIR/valgrind_test_proto.log" \
        ./bin/test_proto > /dev/null 2>&1 || true
    
    if [ -f "$RESULTS_DIR/valgrind_test_proto.log" ]; then
        LEAKS=$(grep "definitely lost" "$RESULTS_DIR/valgrind_test_proto.log" | tail -1 || echo "0 bytes")
        echo "test_proto: $LEAKS"
        echo "test_proto: $LEAKS" >> "$REPORT_FILE"
    fi
fi

if [ -f "./bin/test_shm" ]; then
    valgrind \
        --leak-check=full \
        --error-exitcode=1 \
        --log-file="$RESULTS_DIR/valgrind_test_shm.log" \
        ./bin/test_shm > /dev/null 2>&1 || true
    
    if [ -f "$RESULTS_DIR/valgrind_test_shm.log" ]; then
        LEAKS=$(grep "definitely lost" "$RESULTS_DIR/valgrind_test_shm.log" | tail -1 || echo "0 bytes")
        echo "test_shm: $LEAKS"
        echo "test_shm: $LEAKS" >> "$REPORT_FILE"
    fi
fi

echo "" >> "$REPORT_FILE"

# 測試 3: 檢查 metrics tool
echo "[3/3] Checking metrics tool memory leaks..."
echo "" >> "$REPORT_FILE"
echo "=== Metrics Tool Memory Check ===" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 建立測試用的 shared memory
./bin/server --port 9998 --workers 1 --shm /ns_valgrind_metrics > /dev/null 2>&1 &
SERVER_PID=$!
sleep 0.5

if kill -0 $SERVER_PID 2>/dev/null; then
    valgrind \
        --leak-check=full \
        --error-exitcode=1 \
        --log-file="$RESULTS_DIR/valgrind_metrics.log" \
        ./bin/metrics /ns_valgrind_metrics > /dev/null 2>&1 || true
    
    if [ -f "$RESULTS_DIR/valgrind_metrics.log" ]; then
        LEAKS=$(grep "definitely lost" "$RESULTS_DIR/valgrind_metrics.log" | tail -1 || echo "0 bytes")
        echo "metrics: $LEAKS"
        echo "metrics: $LEAKS" >> "$REPORT_FILE"
    fi
    
    kill -INT $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
fi

rm -f /dev/shm/ns_valgrind_metrics 2>/dev/null || true

echo "" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"
echo "Detailed logs available in:" >> "$REPORT_FILE"
echo "  - $RESULTS_DIR/valgrind_server.log" >> "$REPORT_FILE"
echo "  - $RESULTS_DIR/valgrind_test_*.log" >> "$REPORT_FILE"
echo "  - $RESULTS_DIR/valgrind_metrics.log" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"

echo ""
echo "=========================================="
echo "Memory check complete!"
echo "=========================================="
echo ""
echo "Report saved to: $REPORT_FILE"
echo ""
echo "To view detailed logs:"
echo "  cat $RESULTS_DIR/valgrind_server.log"
echo "  cat $RESULTS_DIR/valgrind_test_proto.log"
echo "  cat $RESULTS_DIR/valgrind_test_shm.log"
echo "  cat $RESULTS_DIR/valgrind_metrics.log"
echo ""

# 顯示摘要
cat "$REPORT_FILE"
