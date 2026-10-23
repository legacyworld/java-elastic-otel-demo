#!/bin/bash
# Redis VM: Redis をインストールし内部IPで待ち受ける (アクセス元は firewall で App VM に限定)
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y redis-server curl

INTERNAL_IP=$(curl -fsS -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

CONF=/etc/redis/redis.conf
sed -i -E "s/^bind .*/bind 127.0.0.1 -::1 ${INTERNAL_IP}/" "$CONF"
sed -i -E "s/^protected-mode .*/protected-mode no/" "$CONF"

systemctl enable redis-server
systemctl restart redis-server
