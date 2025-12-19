#!/usr/bin/env bash
set -euo pipefail

# Real Test runner (Linux-only).
# - Builds binaries
# - Starts server in background
# - Runs a test matrix (connections, mix, worker scaling)
# - Aggregates output into results/runs.csv
#
# Usage:
#   bash scripts/run_real_tests.sh
#   HOST=127.0.0.1 PORT=9000 bash scripts/run_real_tests.sh
#
# Requirements:
# - bash, make
# - gnuplot (only needed for plotting scripts, not for this runner)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-9000}"
SHM="${SHM:-/ns_trading_chat}"

DURATION="${DURATION:-30}"      # seconds per run
THREADS="${THREADS:-16}"

SERVER_BIN="${SERVER_BIN:-./bin/server}"
CLIENT_BIN="${CLIENT_BIN:-./bin/client}"

OUT_DIR="${OUT_DIR:-results}"
RUNS_CSV="${OUT_DIR}/runs.csv"
SERVER_LOG="${OUT_DIR}/server.log"

mkdir -p "$OUT_DIR"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -INT "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[1/4] Building..."
make -s clean && make -s -j

write_header() {
  cat >"$RUNS_CSV" <<'CSV'
run_id,scenario,host,port,connections,threads,duration_s,total,ok,err,rps,p50_us,p95_us,p99_us
CSV
}

append_run() {
  local run_id="$1"
  local scenario="$2"
  local tmp_csv="$3"
  # Take the single data line from the client output and prefix run_id + scenario
  local line
  line="$(tail -n +2 "$tmp_csv" | head -n 1)"
  echo "${run_id},${scenario},${line}" >>"$RUNS_CSV"
}

start_server() {
  local workers="$1"
  echo "[2/4] Starting server: workers=${workers} port=${PORT} shm=${SHM}"
  : >"$SERVER_LOG"
  "$SERVER_BIN" --port "$PORT" --workers "$workers" --shm "$SHM" >>"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
  # Wait briefly for server to bind
  sleep 0.5
}

stop_server() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Stopping server pid=${SERVER_PID}"
    kill -INT "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  unset SERVER_PID || true
  sleep 0.2
}

run_client() {
  local connections="$1"
  local mix="$2"
  local out_csv="$3"
  local payload_size="${4:-32}"  # Default 32 bytes if not specified
  "$CLIENT_BIN" \
    --host "$HOST" \
    --port "$PORT" \
    --connections "$connections" \
    --threads "$THREADS" \
    --duration "$DURATION" \
    --mix "$mix" \
    --payload-size "$payload_size" \
    --out "$out_csv"
}

write_header

run_id=0

echo "[3/4] Running test matrix..."

# Worker scaling matrix
for workers in 1 2 4 8; do
  start_server "$workers"

  # 100 connections / mixed
  run_id=$((run_id + 1))
  tmp="${OUT_DIR}/tmp-${run_id}.csv"
  scenario="w${workers}_c100_mixed"
  echo "Run ${run_id}: ${scenario}"
  run_client 100 mixed "$tmp"
  append_run "$run_id" "$scenario" "$tmp"

  # 200 connections / trade-heavy
  run_id=$((run_id + 1))
  tmp="${OUT_DIR}/tmp-${run_id}.csv"
  scenario="w${workers}_c200_trade-heavy"
  echo "Run ${run_id}: ${scenario}"
  run_client 200 trade-heavy "$tmp"
  append_run "$run_id" "$scenario" "$tmp"

  stop_server
done

# Payload size sweep (32B → 256B → 1KB)
echo "[3b/4] Payload size sweep..."
start_server 4

for payload_size in 32 256 1024; do
  run_id=$((run_id + 1))
  tmp="${OUT_DIR}/tmp-${run_id}.csv"
  scenario="w4_c100_mixed_p${payload_size}"
  echo "Run ${run_id}: ${scenario} (payload=${payload_size}B)"
  run_client 100 mixed "$tmp" "$payload_size"
  append_run "$run_id" "$scenario" "$tmp"
done

stop_server

echo "[4/4] Done."
echo "- Results: ${RUNS_CSV}"
echo "- Server log: ${SERVER_LOG}"
echo "Next: gnuplot -c scripts/plot_latency.gp ${RUNS_CSV} ${OUT_DIR}/latency.png"
echo "      gnuplot -c scripts/plot_throughput.gp ${RUNS_CSV} ${OUT_DIR}/throughput.png"




