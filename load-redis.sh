#!/bin/bash
# Redis VM に負荷スクリプトを転送し、Redis ブロック (Lua) + stress-ng を同時に実行する
# 使い方: ./load-redis.sh [DUTY%] [DURATION秒] [BURN_MS] [CPU_LOAD%]
#   DUTY      Redis を Lua でブロックする稼働率 1-99 (既定 50)。アプリの遅延と Redis コアの CPU に効く
#   DURATION  実行時間(秒) (既定 300)
#   BURN_MS   1回のブロック時間 ms (既定 100)。大きいほどアプリの遅延が増える
#   CPU_LOAD  stress-ng の負荷率 % (既定 90, 0 で無効)。VM 全体の CPU 使用率を押し上げる
# Ctrl-C で両方停止する
set -euo pipefail
cd "$(dirname "$0")"

DUTY=${1:-50}; DURATION=${2:-300}; BURN_MS=${3:-100}; CPU_LOAD=${4:-90}
for v in DUTY DURATION BURN_MS CPU_LOAD; do
  [[ ${!v} =~ ^[0-9]+$ ]] || { echo "$v は整数で指定してください" >&2; exit 1; }
done

VM=$(terraform output -raw redis_instance_name)
ZONE=$(terraform console <<< var.zone | tr -d '"')
PROJECT=$(terraform console <<< var.project_id | tr -d '"')
GC=(--zone "$ZONE" --project "$PROJECT" --tunnel-through-iap)

gcloud compute scp "${GC[@]}" scripts/redis-load.sh scripts/remote-redis-load.sh "$VM":/tmp/
# -t: Ctrl-C をリモートに伝え、stress-ng まで確実に止める
gcloud compute ssh "$VM" "${GC[@]}" -- -t \
  "bash /tmp/remote-redis-load.sh $DUTY $DURATION $BURN_MS $CPU_LOAD"
