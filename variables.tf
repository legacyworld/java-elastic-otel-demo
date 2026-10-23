variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "zone" {
  type    = string
  default = "asia-northeast1-a"
}

# リソース名のプレフィックス。VM は "<prefix>-app" / "<prefix>-redis"
variable "name_prefix" {
  type    = string
  default = "otel-demo"
}

variable "app_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "redis_machine_type" {
  type    = string
  default = "e2-small"
}

variable "app_disk_size_gb" {
  type    = number
  default = 30
}

variable "redis_disk_size_gb" {
  type    = number
  default = 20
}

# アプリ(8080)と OTLP プロキシ(4318)を公開する送信元。既定は全公開
# 絞る場合は自分のIPなどを指定 (例: ["203.0.113.10/32"])
variable "http_source_ranges" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# 既定は作成日(2026-10-22)の1ヶ月後。指定する場合は小文字/数字/-/_ のみ (例: 2026-12-31)
variable "keep_until" {
  type    = string
  default = "2026-11-22"
}
