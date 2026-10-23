#!/bin/bash
# Redis VM 上で実行: stress-ng (CPU 全体の押し上げ) と redis-load.sh (Redis ブロックによる遅延) を同時に動かす
# 使い方: remote-redis-load.sh DUTY DURATION BURN_MS CPU_LOAD
#   CPU_LOAD  stress-ng の負荷率 % (0 で stress-ng を使わない)
set -euo pipefail

DUTY=${1:-50}
DURATION=${2:-300}
BURN_MS=${3:-100}
CPU_LOAD=${4:-90}
DIR=$(dirname "$0")

if [ "$CPU_LOAD" -gt 0 ] && ! command -v stress-ng >/dev/null; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y stress-ng
fi

PIDS=()
cleanup() { [ ${#PIDS[@]} -eq 0 ] || kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

if [ "$CPU_LOAD" -gt 0 ]; then
  # Redis が使うコア以外を埋める (vCPU 数 - 1)。1 vCPU の場合は 1
  WORKERS=$(( $(nproc) > 1 ? $(nproc) - 1 : 1 ))
  stress-ng --cpu "$WORKERS" --cpu-load "$CPU_LOAD" --timeout "${DURATION}s" >/dev/null 2>&1 &
  PIDS+=($!)
  echo "stress-ng: workers=${WORKERS} cpu-load=${CPU_LOAD}% duration=${DURATION}s"
fi

bash "$DIR/redis-load.sh" "$DUTY" "$DURATION" "$BURN_MS"
