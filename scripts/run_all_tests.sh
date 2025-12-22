#!/usr/bin/env bash
set -euo pipefail

# 快速執行全部測試與實測腳本的入口：
# - 在 Linux 上建議流程：
#     bash scripts/run_all_tests.sh
# - 步驟：
#   1) make -j （建置 server/client/libs/tests）
#   2) make unit-test
#   3) make system-test （會啟動短時間 server + client 壓測）
#   4) 選擇性執行 scripts/run_real_tests.sh ＋ gnuplot 產生圖表

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[run-all-tests] build (make -j)..."
make -j

echo "[run-all-tests] unit tests..."
make unit-test

echo "[run-all-tests] system tests..."
make system-test

if [[ "${RUN_REAL_TESTS:-0}" == "1" ]]; then
  echo "[run-all-tests] real tests (scripts/run_real_tests.sh)..."
  bash scripts/run_real_tests.sh

  if command -v gnuplot >/dev/null 2>&1; then
    echo "[run-all-tests] 產生 latency/throughput 圖表..."
    gnuplot -c scripts/plot_latency.gp results/runs.csv results/latency.png || true
    gnuplot -c scripts/plot_throughput.gp results/runs.csv results/throughput.png || true
  else
    echo "[run-all-tests] 系統未安裝 gnuplot，略過圖表產生。"
  fi
else
  echo "[run-all-tests] 跳過 scripts/run_real_tests.sh（如需執行請設置 RUN_REAL_TESTS=1）。"
fi

echo "[run-all-tests] 全部完成。"


