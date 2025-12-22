#!/usr/bin/env bash
set -euo pipefail

# Cross-worker chat broadcast demo 腳本
# ------------------------------------
# 這個腳本會：
#   1) 啟動 4 個 worker 的 server（背景）
#   2) 提示你在另外兩個 zsh 視窗執行 ./bin/interactive（userA / userB）
#   3) 在畫面上顯示完整的 demo 步驟，方便你截圖當證據
#
# 使用方式：
#   bash scripts/demo_cross_worker_chat.sh
#

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
PORT="${PORT:-9000}"
SHM_NAME="${SHM_NAME:-/ns_trading_chat_demo_chat}"

cd "$ROOT_DIR"

if [[ ! -x "$BIN_DIR/server" || ! -x "$BIN_DIR/interactive" ]]; then
  echo "[cross-worker-chat] 先執行 make -j 產生 bin/server 與 bin/interactive"
  exit 1
fi

mkdir -p "$ROOT_DIR/results"

echo "[cross-worker-chat] 啟動 server (workers=4, port=$PORT, shm=$SHM_NAME)..."
"$BIN_DIR/server" --port "$PORT" --workers 4 --shm "$SHM_NAME" >"$ROOT_DIR/results/cross_worker_chat_server.log" 2>&1 &
SERVER_PID=$!
sleep 1

cleanup() {
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[cross-worker-chat] 優雅關閉 server..."
    kill -INT "$SERVER_PID" || true
    wait "$SERVER_PID" || true
  fi
}
trap cleanup EXIT

cat <<EOF

======================================================================
 Cross-worker CHAT_BROADCAST Demo 步驟
======================================================================

1) 在「第一個」 zsh 視窗執行 (userA)：

    cd $ROOT_DIR
    ./bin/interactive --host 127.0.0.1 --port $PORT --user userA

   登入成功後，在互動式介面輸入：

    join 0
    chat hello-from-A

2) 在「第二個」 zsh 視窗執行 (userB)：

    cd $ROOT_DIR
    ./bin/interactive --host 127.0.0.1 --port $PORT --user userB

   一樣輸入：

    join 0
    chat hello-from-B

3) 預期畫面：
   - server log (results/cross_worker_chat_server.log) 中可看到多個 worker pid。
   - userA 視窗會看到：
       [Room 0] You: hello-from-A
       [Room 0] User <id>: hello-from-B
   - userB 視窗會看到：
       [Room 0] You: hello-from-B
       [Room 0] User <id>: hello-from-A

   這兩個 interactive client 可能連到不同的 worker，
   但都能收到對方訊息，證明 cross-worker broadcast 正常。

4) 建議擷取一張截圖，包含：
   - server 視窗（顯示 Server starting + Worker started）
   - userA interactive 視窗
   - userB interactive 視窗

   並將截圖存成：

   docs/screenshots/cross_worker_chat.png

----------------------------------------------------------------------
 完成後，按 Ctrl+C 回到這個腳本視窗即可停止 server。
----------------------------------------------------------------------

EOF

# 等待使用者手動 Ctrl+C 觸發 trap cleanup
while true; do
  sleep 1
done


