terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  app_name   = "${var.name_prefix}-app"
  redis_name = "${var.name_prefix}-redis"

  # GCP labels: keys/values must be lowercase letters, digits, "_" or "-"
  labels = {
    division   = "field"
    org        = "sa"
    keep-until = var.keep_until
    team       = "example-team"
    project    = "otel-demo"
  }
}

data "google_compute_network" "default" {
  name = "default"
}

# ---------------------------------------------------------------
# Firewall (firewall はラベル非対応。target_tags で VM に紐付ける)
# ---------------------------------------------------------------

# IAP (35.235.240.0/20) 経由の SSH のみ許可 (両 VM)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh"
  network = data.google_compute_network.default.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.app_name, local.redis_name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# App VM: Spring Boot(8080) と NGINX OTLP プロキシ(4318) を公開
resource "google_compute_firewall" "allow_app" {
  name    = "${var.name_prefix}-allow-app"
  network = data.google_compute_network.default.name

  direction     = "INGRESS"
  source_ranges = var.http_source_ranges
  target_tags   = [local.app_name]

  allow {
    protocol = "tcp"
    ports    = ["8080", "4318"]
  }
}

# Redis VM: App VM からの 6379 のみ許可
resource "google_compute_firewall" "allow_redis_from_app" {
  name    = "${var.name_prefix}-allow-redis"
  network = data.google_compute_network.default.name

  direction   = "INGRESS"
  source_tags = [local.app_name]
  target_tags = [local.redis_name]

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }
}

# ---------------------------------------------------------------
# VM
# ---------------------------------------------------------------

resource "google_compute_instance" "redis" {
  name         = local.redis_name
  machine_type = var.redis_machine_type
  zone         = var.zone
  tags         = [local.redis_name]
  labels       = local.labels

  metadata_startup_script = file("${path.module}/scripts/startup-redis.sh")

  boot_disk {
    initialize_params {
      image  = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size   = var.redis_disk_size_gb
      type   = "pd-balanced"
      labels = local.labels
    }
  }

  network_interface {
    network = data.google_compute_network.default.self_link

    # パッケージ取得用の一時的な外部IP (インバウンドは firewall で遮断)
    access_config {}
  }
}

resource "google_compute_instance" "app" {
  name         = local.app_name
  machine_type = var.app_machine_type
  zone         = var.zone
  tags         = [local.app_name]
  labels       = local.labels

  metadata = {
    nginx-template = file("${path.module}/nginx/otlp-proxy.conf.template")
  }

  metadata_startup_script = file("${path.module}/scripts/startup-app.sh")

  boot_disk {
    initialize_params {
      image  = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size   = var.app_disk_size_gb
      type   = "pd-balanced"
      labels = local.labels
    }
  }

  network_interface {
    network = data.google_compute_network.default.self_link

    access_config {}
  }
}
