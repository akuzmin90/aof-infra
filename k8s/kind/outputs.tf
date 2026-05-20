output "jenkins_admin_password" {
  description = "Generated local Jenkins admin password."
  value       = random_password.jenkins_admin.result
  sensitive   = true
}

output "local_frontend_url" {
  description = "Local frontend URL served through ingress from the MinIO-backed bucket."
  value       = "https://dev.hitmakers.ru"
}

output "local_minio_endpoint" {
  description = "In-cluster MinIO S3 endpoint for Jenkins jobs."
  value       = "http://minio.minio.svc.cluster.local:9000"
}

output "local_frontend_bucket" {
  description = "Local MinIO bucket used for frontend assets."
  value       = module.minio.bucket_name
}
