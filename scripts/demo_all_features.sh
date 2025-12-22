#!/usr/bin/env bash
set -euo pipefail

# 快速示範「所有核心功能」的一鍵腳本：
# - build
# - unit 測試 (proto + shm)
# - system 測試 (短時間 mixed + trade-heavy + encryption)
# - 多種 workload demo（mixed / trade-heavy / chat-heavy）
# - 顯示 shared memory metrics
#
# 使用方式：
#   bash scripts/demo_all_features.sh
#

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
RESULTS_DIR="$ROOT_DIR/results"
PORT="${PORT:-9000}"
SHM_NAME="${SHM_NAME:-/ns_trading_chat_demo_all}"

mkdir -p "$RESULTS_DIR"

echo "[demo-all] 1/5 build (make -j)..."
cd "$ROOT_DIR"
make -j

echo "[demo-all] 2/5 unit tests..."
make unit-test

echo "[demo-all] 3/5 system tests (scripts/test_system.sh)..."
make system-test

echo "[demo-all] 4/5 start demo server..."
if [[ ! -x "$BIN_DIR/server" ]]; then
  echo "  缺少 bin/server，請先在 Linux 上執行: make"
  exit 1
fi
if [[ ! -x "$BIN_DIR/client" ]]; then
  echo "  缺少 bin/client，請先在 Linux 上執行: make"
  exit 1
fi
if [[ ! -x "$BIN_DIR/metrics" ]]; then
  echo "  缺少 bin/metrics，請先在 Linux 上執行: make"
  exit 1
fi

"$BIN_DIR/server" --port "$PORT" --workers 4 --shm "$SHM_NAME" >"$RESULTS_DIR/demo_server.log" 2>&1 &
SERVER_PID=$!
sleep 1

cleanup() {
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[demo-all] 關閉 demo server..."
    kill -INT "$SERVER_PID" || true
    wait "$SERVER_PID" || true
  fi
}
trap cleanup EXIT

echo "[demo-all] 4a) mixed workload demo..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 100 --threads 16 --duration 10 \
  --mix mixed --out "$RESULTS_DIR/demo_mixed.csv"

echo "[demo-all] 4b) trade-heavy workload demo..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 100 --threads 16 --duration 10 \
  --mix trade-heavy --out "$RESULTS_DIR/demo_trade.csv"

echo "[demo-all] 4c) chat-heavy workload demo (含較大 payload)..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 100 --threads 16 --duration 10 \
  --mix chat-heavy --payload-size 256 --out "$RESULTS_DIR/demo_chat.csv"

echo "[demo-all] 4d) trade-heavy + XOR encryption demo..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 50 --threads 8 --duration 5 \
  --mix trade-heavy --encrypt --out "$RESULTS_DIR/demo_trade_encrypt.csv"

echo "[demo-all] 5/5 shared memory metrics..."
"$BIN_DIR/metrics" "$SHM_NAME" >"$RESULTS_DIR/demo_metrics.txt" || true

echo
echo "[demo-all] 完成！重點輸出："
echo "  - $RESULTS_DIR/demo_server.log"
echo "  - $RESULTS_DIR/demo_mixed.csv"
echo "  - $RESULTS_DIR/demo_trade.csv"
echo "  - $RESULTS_DIR/demo_chat.csv"
echo "  - $RESULTS_DIR/demo_trade_encrypt.csv"
echo "  - $RESULTS_DIR/demo_metrics.txt"
echo
echo "你可以用這些檔案搭配 README / AUDITING 報告，以及截圖作為所有功能的證據。"


