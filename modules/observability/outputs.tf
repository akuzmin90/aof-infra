output "namespace" {
  description = "Namespace where observability components are deployed."
  value       = var.namespace
}

output "grafana_service_name" {
  description = "Grafana Kubernetes service name."
  value       = "grafana"
}

output "alloy_gateway_service_name" {
  description = "Alloy gateway Kubernetes service name for external log ingestion."
  value       = "alloy-gateway"
}

output "grafana_admin_username" {
  description = "Grafana admin username."
  value       = "admin"
}

output "grafana_admin_password" {
  description = "Grafana admin password."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "loki_bucket" {
  description = "S3 bucket used by Loki."
  value       = var.s3_bucket
}
