#!/bin/bash
# App VM: Java 17 / Gradle / NGINX をインストールする (アプリ本体は deploy.sh で配置)
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

MD=http://metadata.google.internal/computeMetadata/v1/instance/attributes
GRADLE_VERSION=8.7
AGENT_VERSION=1.10.0

apt-get update
apt-get install -y openjdk-17-jdk-headless nginx gettext-base unzip curl

# Gradle (リポジトリに wrapper jar が無いため VM 上で直接用意する)
if [ ! -x /opt/gradle/bin/gradle ]; then
  curl -fsSL -o /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
  unzip -q /tmp/gradle.zip -d /opt
  ln -sfn "/opt/gradle-${GRADLE_VERSION}" /opt/gradle
  rm -f /tmp/gradle.zip
fi

# アプリ用ユーザーとディレクトリ
id otel-demo >/dev/null 2>&1 || useradd --system --home /opt/otel-demo --shell /usr/sbin/nologin otel-demo
install -d -o otel-demo -g otel-demo /opt/otel-demo
install -d -m 0750 -o root -g otel-demo /etc/otel-demo

# Elastic OTel Java Agent
curl -fsSL -o /opt/otel-demo/elastic-otel-javaagent.jar \
  "https://repo1.maven.org/maven2/co/elastic/otel/elastic-otel-javaagent/${AGENT_VERSION}/elastic-otel-javaagent-${AGENT_VERSION}.jar"
chown otel-demo:otel-demo /opt/otel-demo/elastic-otel-javaagent.jar

# NGINX 設定テンプレート (metadata から取得)。実際の設定は deploy 時に env 展開して生成
curl -fsSL -H 'Metadata-Flavor: Google' "$MD/nginx-template" -o /etc/nginx/otlp-proxy.conf.template
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx

# systemd unit: .env を bash で source して $OTEL_API_KEY などを展開してから起動
cat > /etc/systemd/system/otel-demo.service <<'UNIT'
[Unit]
Description=Spring Boot OTel demo
After=network-online.target
Wants=network-online.target

[Service]
User=otel-demo
Group=otel-demo
WorkingDirectory=/opt/otel-demo
ExecStart=/bin/bash -c 'set -a; . /etc/otel-demo/app.env; set +a; exec java $JAVA_OPTS -javaagent:/opt/otel-demo/elastic-otel-javaagent.jar -jar /opt/otel-demo/app.jar'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable otel-demo

touch /var/lib/otel-demo-provisioned
