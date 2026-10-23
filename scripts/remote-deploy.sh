#!/bin/bash
# App VM 上で実行: ソースをビルドし、サービスと NGINX を再起動する
# 前提: /tmp/otel-demo-src.tgz (ソース) と /tmp/app.env (環境変数) が配置済み
set -euxo pipefail

# startup script (パッケージ導入) の完了待ち
for _ in $(seq 1 60); do
  [ -f /var/lib/otel-demo-provisioned ] && break
  sleep 10
done
[ -f /var/lib/otel-demo-provisioned ] || { echo "VM のプロビジョニングが未完了です" >&2; exit 1; }

BUILD_DIR=$(mktemp -d)
tar xzf /tmp/otel-demo-src.tgz -C "$BUILD_DIR"
(cd "$BUILD_DIR" && /opt/gradle/bin/gradle --no-daemon bootJar)
sudo install -o otel-demo -g otel-demo -m 0644 "$BUILD_DIR"/build/libs/java-otel-demo-1.0.0.jar /opt/otel-demo/app.jar
rm -rf "$BUILD_DIR"

sudo install -o root -g otel-demo -m 0640 /tmp/app.env /etc/otel-demo/app.env
rm -f /tmp/app.env /tmp/otel-demo-src.tgz

# NGINX 設定を env から生成 (対象変数のみ展開し $request_method などは保持)
sudo bash -c '
  set -a; . /etc/otel-demo/app.env; set +a
  envsubst "\${OTEL_ALLOWED_ORIGIN} \${OTEL_EXPORTER_OTLP_ENDPOINT} \${OTEL_API_KEY}" \
    < /etc/nginx/otlp-proxy.conf.template > /etc/nginx/conf.d/otlp-proxy.conf
  chmod 0640 /etc/nginx/conf.d/otlp-proxy.conf
  chown root:www-data /etc/nginx/conf.d/otlp-proxy.conf
'
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl restart otel-demo
