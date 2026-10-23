#!/bin/bash
# VM 上で実行: Elastic Agent を (再)インストールして Fleet に登録する
# 使い方: remote-install-agent.sh <version> <fleet_url> <enrollment_token>
set -euxo pipefail
VERSION=$1 FLEET_URL=$2 TOKEN=$3

# 既存の Agent があれば削除
if [ -x /usr/bin/elastic-agent ] || [ -d /opt/Elastic/Agent ]; then
  sudo elastic-agent uninstall -f || sudo /opt/Elastic/Agent/elastic-agent uninstall -f
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
NAME=elastic-agent-${VERSION}-linux-x86_64
curl -fsSL -o "$DIR/agent.tgz" "https://artifacts.elastic.co/downloads/beats/elastic-agent/${NAME}.tar.gz"
tar xzf "$DIR/agent.tgz" -C "$DIR"
(cd "$DIR/$NAME" && sudo ./elastic-agent install --non-interactive --url="$FLEET_URL" --enrollment-token="$TOKEN")
