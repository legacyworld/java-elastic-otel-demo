# CLAUDE.md

GCP の 2 VM 構成 (Terraform) のデモ。詳細は [README.md](README.md)。

## 作業ルール

- 参照してよいのはこのリポジトリのみ。それ以外のディレクトリは明示的に頼まれない限り探索しない
- 不明点は仮定で進めず、先にユーザーへ確認する
- ホスト OS にソフトを入れない。必要なものは VM 側 (startup script) で入れる。ローカルに Java/Gradle は使わない
- 返答は日本語

## GCP の制約

- 全 VM とブートディスクに `local.labels` を付与する (division=field, org=sa, keep-until, team=example-team, project=otel-demo)。値は小文字・数字・`-`・`_` のみ
- `keep-until` は作成日の 1 ヶ月後 (既定 `2026-11-22`)
- firewall はラベル非対応。target_tags / source_tags で紐付ける
- SSH は IAP (35.235.240.0/20) 経由のみ許可。外部公開の SSH は作らない
- project は `your-gcp-project-id` (要変更)、zone は `asia-northeast1-a` (variables.tf の既定)

## 構成上の要点

- App VM: Spring Boot (systemd `otel-demo`) と NGINX (4318, OTLP プロキシ)。Redis VM: Redis のみ、6379 は App VM タグからのみ
- App VM のビルドは VM 上で行う (リポジトリに gradle-wrapper.jar が無いため Gradle 8.7 を startup script で導入)
- NGINX テンプレートは instance metadata `nginx-template` 経由で VM に渡し、`scripts/remote-deploy.sh` が `envsubst` で `/etc/nginx/conf.d/otlp-proxy.conf` を生成する。展開する変数は `OTEL_ALLOWED_ORIGIN` / `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_API_KEY` のみ (`$request_method` 等を壊さないため)
- `deploy.sh` は `OTEL_ALLOWED_ORIGIN` / `*REDIS_HOST` / `*REDIS_PORT` を terraform output で上書きする。`.env` に `<...>` が残っていると配置前に止まる
- 環境変数は `/etc/otel-demo/app.env` に置き、systemd と envsubst の両方が bash で `source` して展開する
- `OTEL_EXPORTER_OTLP_ENDPOINT` は GCP から解決できる公開エンドポイントを使う (`ingest.private.*` は不可)

## よく使うコマンド

```bash
terraform validate && terraform fmt -check
terraform apply && ./deploy.sh
terraform output -raw ssh_app | sh
sudo journalctl -u otel-demo -f      # App VM 上
```

## 注意

- `.env`、`terraform.tfvars`、`*.tfstate` は秘密情報を含む。内容を表示・コミットしない
- `terraform apply` / `destroy` や `deploy.sh` は実環境に影響するため、ユーザーの指示なしに実行しない
- アプリ側の修正は `app/` 内で行う
