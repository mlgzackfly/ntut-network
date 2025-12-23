#!/usr/bin/env bash
# Static Analysis Script using cppcheck and clang-tidy
# 執行靜態程式碼分析，檢查潛在問題

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RESULTS_DIR="$ROOT/results"
mkdir -p "$RESULTS_DIR"

REPORT_FILE="$RESULTS_DIR/static_analysis.txt"

echo "=========================================="
echo "Static Code Analysis"
echo "=========================================="
echo ""

# 清空報告檔案
: > "$REPORT_FILE"

echo "=========================================" >> "$REPORT_FILE"
echo "Static Analysis Report" >> "$REPORT_FILE"
echo "Date: $(date)" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 檢查 cppcheck
HAS_CPPCHECK=false
if command -v cppcheck &> /dev/null; then
    HAS_CPPCHECK=true
    echo "✓ cppcheck found: $(cppcheck --version)"
else
    echo "⚠️  cppcheck not installed"
    echo ""
    echo "To install on Ubuntu/Debian:"
    echo "  sudo apt-get install cppcheck"
    echo ""
fi

# 檢查 clang-tidy
HAS_CLANG_TIDY=false
if command -v clang-tidy &> /dev/null; then
    HAS_CLANG_TIDY=true
    echo "✓ clang-tidy found: $(clang-tidy --version | head -1)"
else
    echo "⚠️  clang-tidy not installed"
    echo ""
    echo "To install on Ubuntu/Debian:"
    echo "  sudo apt-get install clang-tidy"
    echo ""
fi

if [ "$HAS_CPPCHECK" = false ] && [ "$HAS_CLANG_TIDY" = false ]; then
    echo "No static analysis tools available. Exiting."
    exit 0
fi

echo ""

# 執行 cppcheck
if [ "$HAS_CPPCHECK" = true ]; then
    echo "[1/2] Running cppcheck..."
    echo "" >> "$REPORT_FILE"
    echo "=== cppcheck Analysis ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    cppcheck \
        --enable=all \
        --suppress=missingIncludeSystem \
        --suppress=unusedFunction \
        --std=c11 \
        --platform=unix64 \
        --inline-suppr \
        -I include \
        src/ 2>&1 | tee -a "$REPORT_FILE" || true
    
    echo "" >> "$REPORT_FILE"
    echo "✓ cppcheck complete"
else
    echo "[1/2] Skipping cppcheck (not installed)"
    echo "cppcheck: Not installed" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# 執行 clang-tidy
if [ "$HAS_CLANG_TIDY" = true ]; then
    echo "[2/2] Running clang-tidy..."
    echo "" >> "$REPORT_FILE"
    echo "=== clang-tidy Analysis ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 尋找所有 C 檔案
    find src -name "*.c" | while read -r file; do
        echo "Checking: $file" >> "$REPORT_FILE"
        clang-tidy "$file" \
            -checks='*,-llvmlibc-*,-altera-*,-fuchsia-*,-android-*' \
            -- -Iinclude -std=c11 2>&1 | \
            grep -v "warnings generated" | \
            tee -a "$REPORT_FILE" || true
        echo "" >> "$REPORT_FILE"
    done
    
    echo "✓ clang-tidy complete"
else
    echo "[2/2] Skipping clang-tidy (not installed)"
    echo "clang-tidy: Not installed" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"
echo "Analysis complete" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"

echo ""
echo "=========================================="
echo "Static analysis complete!"
echo "=========================================="
echo ""
echo "Report saved to: $REPORT_FILE"
echo ""
echo "Summary:"
if [ "$HAS_CPPCHECK" = true ]; then
    ERROR_COUNT=$(grep -c "error:" "$REPORT_FILE" || echo "0")
    WARNING_COUNT=$(grep -c "warning:" "$REPORT_FILE" || echo "0")
    echo "  Errors: $ERROR_COUNT"
    echo "  Warnings: $WARNING_COUNT"
fi
echo ""
echo "To view full report:"
echo "  cat $REPORT_FILE"
echo ""
