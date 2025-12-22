#!/usr/bin/env bash
set -euo pipefail

# 自動化系統測試腳本（需在 Linux 上執行）：
# - 啟動 server（背景）
# - 執行短時間壓測（含 encryption 路徑）
# - 呼叫 metrics 工具檢視指標
# - 優雅關閉 server

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
RESULTS_DIR="$ROOT_DIR/results"
PORT="${PORT:-9000}"
SHM_NAME="${SHM_NAME:-/ns_trading_chat_test}"

mkdir -p "$RESULTS_DIR"

echo "[system-test] 檢查必需執行檔是否存在..."
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

echo "[system-test] 啟動伺服器 (port=$PORT, shm=$SHM_NAME)..."
"$BIN_DIR/server" --port "$PORT" --workers 2 --shm "$SHM_NAME" >"$RESULTS_DIR/system_server.log" 2>&1 &
SERVER_PID=$!
sleep 1

cleanup() {
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[system-test] 優雅關閉伺服器..."
    kill -INT "$SERVER_PID" || true
    wait "$SERVER_PID" || true
  fi
}
trap cleanup EXIT

echo "[system-test] 執行短時間 mixed 壓測..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 50 --threads 8 --duration 5 \
  --mix mixed --out "$RESULTS_DIR/system_mixed.csv"

echo "[system-test] 執行啟用 XOR encryption 的 trade-heavy 壓測..."
"$BIN_DIR/client" --host 127.0.0.1 --port "$PORT" \
  --connections 50 --threads 8 --duration 5 \
  --mix trade-heavy --encrypt --out "$RESULTS_DIR/system_trade_encrypt.csv"

echo "[system-test] 讀取 shared memory metrics..."
"$BIN_DIR/metrics" "$SHM_NAME" >"$RESULTS_DIR/system_metrics.txt" || true

echo "[system-test] 完成，輸出檔案位於: $RESULTS_DIR"

exit 0


