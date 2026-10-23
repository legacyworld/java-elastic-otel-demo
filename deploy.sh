#!/bin/bash
# Elastic Agent を両 VM に再インストールし、アプリを App VM に配置する (terraform apply 後に実行)
# 使い方: ./deploy.sh   (./.env が必要。.env_sample をコピーして編集)
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo ".env がありません (cp .env_sample .env して編集)" >&2; exit 1; }

# .env から値を取り出す (source するとプレースホルダで構文エラーになるため grep)
envval() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -E "s/^[\"']|[\"']\$//g"; }
KIBANA_URL=$(envval KIBANA_URL); KIBANA_URL=${KIBANA_URL%/}
KIBANA_API_KEY=$(envval KIBANA_API_KEY)
POLICY_NAME=$(envval KIBANA_AGENT_POLICY_NAME); POLICY_NAME=${POLICY_NAME:-java_otel_test}
{ [ -n "$KIBANA_URL" ] && [ -n "$KIBANA_API_KEY" ]; } || { echo ".env に KIBANA_URL / KIBANA_API_KEY がありません" >&2; exit 1; }

kb() { # kb METHOD PATH [curl args...]
  local m=$1 p=$2; shift 2
  curl -fsS -X "$m" "$KIBANA_URL$p" -H "Authorization: ApiKey $KIBANA_API_KEY" \
    -H 'kbn-xsrf: true' -H 'elastic-api-version: 2023-10-31' -H 'Content-Type: application/json' "$@"
}

tf() { terraform output -raw "$1"; }
APP=$(tf app_instance_name)
REDIS=$(tf redis_instance_name)
APP_IP=$(tf app_external_ip)
REDIS_IP=$(tf redis_internal_ip)
ZONE=$(terraform console <<< var.zone | tr -d '"')
PROJECT=$(terraform console <<< var.project_id | tr -d '"')
GC=(--zone "$ZONE" --project "$PROJECT" --tunnel-through-iap)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# deploy.sh が設定するキーは .env から除外 (サンプルのプレースホルダ <...> が bash 構文エラーになるため)
grep -Ev '^(KIBANA_URL|KIBANA_API_KEY|KIBANA_AGENT_POLICY_NAME|OTEL_ALLOWED_ORIGIN|SPRING_REDIS_HOST|SPRING_REDIS_PORT|REDIS_HOST|REDIS_PORT)=' .env > "$WORK/app.env"

# 未編集のプレースホルダが残っていないか確認
if PLACEHOLDERS=$(grep -nE '^[A-Za-z_]+=.*<[^>]+>' "$WORK/app.env"); then
  echo ".env に未編集のプレースホルダ (<...>) があります:" >&2
  echo "$PLACEHOLDERS" >&2
  exit 1
fi
for k in OTEL_EXPORTER_OTLP_ENDPOINT OTEL_API_KEY; do
  grep -qE "^${k}=.+" "$WORK/app.env" || { echo ".env に ${k} がありません" >&2; exit 1; }
done

# Terraform で決まる値 (IP) を追記
cat >> "$WORK/app.env" <<ENV

# --- deploy.sh が terraform output から設定 ---
OTEL_ALLOWED_ORIGIN=http://${APP_IP}:8080
SPRING_REDIS_HOST=${REDIS_IP}
SPRING_REDIS_PORT=6379
REDIS_HOST=${REDIS_IP}
REDIS_PORT=6379
ENV

# --- Elastic Agent: ポリシー内の既存 Agent を unregister → 両 VM に再インストール ---
POLICY_ID=$(kb GET "/api/fleet/agent_policies?perPage=100" | jq -r --arg n "$POLICY_NAME" '.items[] | select(.name==$n) | .id' | head -n1)
[ -n "$POLICY_ID" ] || { echo "Agent policy '$POLICY_NAME' が見つかりません" >&2; exit 1; }

AGENT_IDS=$(kb GET "/api/fleet/agents?perPage=1000&showInactive=true" --get --data-urlencode "kuery=policy_id:\"$POLICY_ID\"" | jq -r '.items[].id')
for id in $AGENT_IDS; do
  echo "unregister: $id"
  kb DELETE "/api/fleet/agents/$id" >/dev/null
done

AGENT_VERSION=$(kb GET /api/fleet/agents/available_versions | jq -r '.items[0]')
FLEET_URL=$(kb GET /api/fleet/fleet_server_hosts | jq -r '([.items[] | select(.is_default)] + .items)[0].host_urls[0]')
TOKEN=$(kb GET "/api/fleet/enrollment_api_keys?perPage=100" | jq -r --arg p "$POLICY_ID" '[.items[] | select(.policy_id==$p and .active)][0].api_key')
for v in AGENT_VERSION FLEET_URL TOKEN; do
  { [ -n "${!v}" ] && [ "${!v}" != null ]; } || { echo "Fleet から ${v} を取得できません" >&2; exit 1; }
done
echo "Elastic Agent ${AGENT_VERSION} / ${FLEET_URL} / policy=${POLICY_NAME}"

for vm in "$APP" "$REDIS"; do
  gcloud compute scp "${GC[@]}" scripts/remote-install-agent.sh "$vm":/tmp/remote-install-agent.sh
  gcloud compute ssh "$vm" "${GC[@]}" --command "bash /tmp/remote-install-agent.sh '$AGENT_VERSION' '$FLEET_URL' '$TOKEN'"
done

tar czf "$WORK/otel-demo-src.tgz" -C app build.gradle settings.gradle src

gcloud compute scp "${GC[@]}" "$WORK/otel-demo-src.tgz" "$WORK/app.env" "$APP":/tmp/
gcloud compute scp "${GC[@]}" scripts/remote-deploy.sh "$APP":/tmp/remote-deploy.sh
gcloud compute ssh "$APP" "${GC[@]}" --command "bash /tmp/remote-deploy.sh"

echo "Frontend: http://${APP_IP}:8080"
