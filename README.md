# GCP 2VM 構成 (Terraform)

Elastic OTel Java Agent を使ったデモを GCP の VM 2 台構成 (Terraform) で動かす。

```
Browser ─► App VM :8080  Spring Boot (+ Elastic OTel Java Agent) ─► Redis VM :6379
        └► App VM :4318  NGINX (apt install) ─► Elastic Cloud (OTLP)
```

| VM | 内容 |
|---|---|
| `<name_prefix>-app` | Java 17 / Spring Boot (systemd: `otel-demo`) / NGINX (OTLP プロキシ 4318) |
| `<name_prefix>-redis` | Redis のみ。6379 は App VM からのみ許可 |

- SSH は IAP 経由のみ (`--tunnel-through-iap`)
- Docker は使わない。NGINX は apt で導入し、設定は `nginx/otlp-proxy.conf.template` から生成

## 前提

- `terraform`、`gcloud` (認証済みで、project に Compute 権限と IAP トンネル権限があること)
- ローカルに Java / Gradle は不要 (ビルドは App VM 上)

## 手順

```bash
terraform init
terraform apply          # VM作成 (パッケージ導入に数分)

cp .env_sample .env      # 下記の値を編集
./deploy.sh              # ソースを App VM に送り、VM上でビルド・起動
```

### `.env` で必ず編集する値

| 変数 | 内容 |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Elastic Cloud の OTLP エンドポイント。**GCP から名前解決できる公開用**を指定する (`ingest.private.…` は PrivateLink 用で GCP からは解決できず NGINX が起動しない) |
| `OTEL_API_KEY` | Elastic Cloud の API キー (Base64) |

`OTEL_ALLOWED_ORIGIN` / `SPRING_REDIS_HOST` / `SPRING_REDIS_PORT` / `REDIS_HOST` / `REDIS_PORT` は `deploy.sh` が `terraform output` の値で上書きするため編集不要。
`<...>` のプレースホルダが残っていると `deploy.sh` が配置前にエラーで止まる。

コードや `.env` を変更したら `./deploy.sh` を再実行する。終了後は `terraform destroy`。

## 運用コマンド

```bash
terraform output -raw ssh_app   | sh     # App VM に SSH
terraform output -raw ssh_redis | sh     # Redis VM に SSH
```

App VM 上:

```bash
sudo journalctl -u otel-demo -f          # Java のコンソールログ (JSON)
sudo journalctl -u otel-demo -n 100 --no-pager
sudo systemctl status otel-demo nginx
sudo journalctl -u nginx                 # NGINX
sudo cat /etc/nginx/conf.d/otlp-proxy.conf
```

## Redis 負荷デモ (`load-redis.sh`)

Redis VM に負荷をかけ、アプリの遅延と CPU 使用率の上昇を結び付けて観察する。ローカルから実行する (スクリプトの転送、VM への `stress-ng` 導入、実行、停止まで自動)。

```bash
./load-redis.sh [DUTY%] [DURATION秒] [BURN_MS] [CPU_LOAD%]
./load-redis.sh                  # 既定: DUTY=50 DURATION=300 BURN_MS=100 CPU_LOAD=90
./load-redis.sh 80 600 200 90    # 遅延を強める
./load-redis.sh 50 300 100 0     # Lua のみ (stress-ng なし)
```

| 引数 | 内容 | 主に効くもの |
|---|---|---|
| `DUTY` | Redis を Lua (`EVAL`) でブロックする稼働率 (1-99) | アプリの遅延、Redis コアの CPU |
| `DURATION` | 実行時間 (秒) | |
| `BURN_MS` | 1 回のブロック時間 (ms、1-1000)。Redis へのコマンドは最大でこの時間待たされる | アプリの遅延 |
| `CPU_LOAD` | `stress-ng` の負荷率 (%)。0 で無効 | VM 全体の CPU 使用率 |

- Redis は単一スレッドのため、Lua だけでは 2 vCPU の VM で CPU 使用率が最大約 50% になる。残りのコアを `stress-ng` で埋めて VM 全体の CPU を押し上げる (遅延への影響はほぼ無い)
- 常時 100% にならないよう、`BURN_MS` だけ回して残りを sleep するため、アプリは応答できる
- アプリが Redis を呼んでいる間 (フロントからリクエストを流している間) に実行しないと遅延は出ない
- 観察のコツ: 負荷なし 2 分 → 負荷あり 3〜5 分 → 停止後 2 分 とすると、遅延と CPU の山が重なって因果関係が分かりやすい
- Ctrl-C で Lua 負荷と `stress-ng` の両方が止まる。`stress-ng` は初回実行時に Redis VM へ自動インストールされる (apt)
- 初回は `DUTY=50 BURN_MS=100` あたりから始め、遅延の出方を見て調整する

## ファイル構成

```
./
├── main.tf / variables.tf / outputs.tf   # VM x2, firewall
├── terraform.tfvars.example              # 変数上書き例 (任意)
├── deploy.sh                             # ローカルから実行するデプロイ
├── load-redis.sh                         # ローカルから実行する Redis 負荷デモ (転送+実行)
├── scripts/
│   ├── startup-app.sh                    # App VM 初期設定 (Java/Gradle/NGINX/systemd)
│   ├── startup-redis.sh                  # Redis VM 初期設定
│   ├── remote-deploy.sh                  # App VM 上でビルド・再起動 (deploy.sh が転送)
│   ├── remote-redis-load.sh              # Redis VM 上で stress-ng + redis-load.sh を実行 (load-redis.sh が転送)
│   └── redis-load.sh                     # Redis VM 上で Lua の EVAL により Redis をブロックして負荷をかける
├── nginx/otlp-proxy.conf.template        # NGINX 設定 (metadata 経由で VM に渡る)
├── app/                                  # アプリのソース (Spring Boot)
└── .env_sample
```

## 注意

- `http_source_ranges` の既定は `0.0.0.0/0` (全公開)。NGINX(4318) は API キーを付与して転送するため、第三者が Elastic Cloud にデータを送れる状態になる。使い終わったら `terraform destroy`。絞る場合は `terraform.tfvars` で指定
- Redis は認証なし (アプリ側が未対応)。firewall (source_tag = App VM) のみで保護
- 外部IPは一時IP。VM を停止/起動すると変わるため、`terraform apply` 後に `./deploy.sh` を再実行
- `app/` は作業ツリーの現状版コピー。元の `src` を変更しても自動では反映されない
- `.env` / `terraform.tfstate` は API キーや構成情報を含むため Git に入れない (`.gitignore` 済み)
