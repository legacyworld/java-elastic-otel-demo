#!/bin/bash
# Redis VM 上で実行する CPU 負荷スクリプト (Lua の EVAL をビジー待ちさせる)
# Redis は単一スレッドなので、EVAL 実行中は他のコマンドがブロックされる。
# そのため「BURN_MS だけ回す → 残りは sleep」を繰り返して稼働率(DUTY %)で負荷を調整する。
#
# 使い方: redis-load.sh [DUTY%] [DURATION秒] [BURN_MS]
#   DUTY      目標の Redis CPU 稼働率 1-99 (既定 50)
#   DURATION  実行時間(秒) 0 で Ctrl-C まで (既定 300)
#   BURN_MS   1回の EVAL でブロックする時間 ms (既定 50)。大きいほど他リクエストの最大遅延が増える
# 環境変数: REDIS_HOST (既定 127.0.0.1), REDIS_PORT (既定 6379)
set -euo pipefail

DUTY=${1:-50}
DURATION=${2:-300}
BURN_MS=${3:-50}
HOST=${REDIS_HOST:-127.0.0.1}
PORT=${REDIS_PORT:-6379}

{ [ "$DUTY" -ge 1 ] && [ "$DUTY" -le 99 ]; } || { echo "DUTY は 1-99 で指定してください" >&2; exit 1; }
# lua-time-limit (既定 5000ms) を超えると他クライアントが BUSY エラーになるため上限を設ける
[ "$BURN_MS" -ge 1 ] && [ "$BURN_MS" -le 1000 ] || { echo "BURN_MS は 1-1000 で指定してください" >&2; exit 1; }

# redis.call('TIME') で経過時間を測って BURN_MS 経過するまで計算を回す (書き込みなし)
LUA='
local burn = tonumber(ARGV[1]) * 1000
local t = redis.call("TIME")
local start = t[1] * 1000000 + t[2]
local x = 0
while true do
  for i = 1, 2000 do x = x + math.sqrt(i) end
  t = redis.call("TIME")
  if (t[1] * 1000000 + t[2]) - start >= burn then break end
end
return 1
'

# 1サイクルの長さ = BURN_MS / DUTY、残りが sleep
SLEEP=$(awk -v b="$BURN_MS" -v d="$DUTY" 'BEGIN { printf "%.3f", b * (100 - d) / d / 1000 }')
echo "load start: duty=${DUTY}% burn=${BURN_MS}ms sleep=${SLEEP}s duration=${DURATION}s target=${HOST}:${PORT}"

trap 'echo; echo "stopped"; exit 0' INT TERM
END=$(( $(date +%s) + DURATION ))
while [ "$DURATION" -eq 0 ] || [ "$(date +%s)" -lt "$END" ]; do
  T0=$(date +%s%N)
  # redis-cli はエラー応答でも終了コード 0 を返すため、応答内容で判定する
  RES=$(redis-cli -h "$HOST" -p "$PORT" EVAL "$LUA" 0 "$BURN_MS" 2>&1) || true
  [ "$RES" = 1 ] || { echo "EVAL 失敗: $RES" >&2; exit 1; }
  # 初回だけ実測時間を表示 (BURN_MS とほぼ一致するはず)
  [ -n "${SHOWN:-}" ] || { echo "first EVAL: $(( ($(date +%s%N) - T0) / 1000000 ))ms"; SHOWN=1; }
  sleep "$SLEEP"
done
echo "done"
