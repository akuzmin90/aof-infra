output "namespace" {
  description = "Namespace where MinIO is installed."
  value       = kubernetes_namespace.minio.metadata[0].name
}

output "service_name" {
  description = "MinIO Kubernetes service name."
  value       = kubernetes_service.minio.metadata[0].name
}

output "bucket_name" {
  description = "Local frontend bucket name."
  value       = "aof-front"
}
