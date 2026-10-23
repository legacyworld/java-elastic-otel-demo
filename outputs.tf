output "app_instance_name" {
  value = google_compute_instance.app.name
}

output "redis_instance_name" {
  value = google_compute_instance.redis.name
}

output "app_external_ip" {
  value = google_compute_instance.app.network_interface[0].access_config[0].nat_ip
}

output "redis_internal_ip" {
  value = google_compute_instance.redis.network_interface[0].network_ip
}

output "app_url" {
  value = "http://${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}:8080"
}

output "ssh_app" {
  value = "gcloud compute ssh ${google_compute_instance.app.name} --zone ${var.zone} --project ${var.project_id} --tunnel-through-iap"
}

output "ssh_redis" {
  value = "gcloud compute ssh ${google_compute_instance.redis.name} --zone ${var.zone} --project ${var.project_id} --tunnel-through-iap"
}
