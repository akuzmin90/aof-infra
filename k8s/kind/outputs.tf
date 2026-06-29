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

output "local_minio_console_url" {
  description = "Local MinIO console URL served through ingress."
  value       = "https://s3.hitmakers.ru"
}

output "local_frontend_bucket" {
  description = "Local MinIO bucket used for frontend assets."
  value       = module.minio.bucket_name
}

output "postgres_jdbc_url" {
  description = "PgBouncer JDBC URL for aof-back inside the local Kubernetes cluster."
  value       = module.postgresql_cluster.jdbc_url
}

output "postgres_direct_jdbc_url" {
  description = "Direct read-write PostgreSQL JDBC URL for admin/maintenance jobs."
  value       = module.postgresql_cluster.direct_jdbc_url
}

output "postgres_username" {
  description = "PostgreSQL application username."
  value       = module.postgresql_cluster.username
}

output "postgres_password" {
  description = "Generated PostgreSQL application password."
  value       = random_password.postgres_app.result
  sensitive   = true
}

output "postgres_dump_bucket" {
  description = "Local MinIO bucket used for manual logical PostgreSQL dumps."
  value       = module.postgresql_cluster.dump_bucket
}

output "postgres_backup_bucket" {
  description = "Local MinIO bucket used for CloudNativePG physical backups and WAL archive."
  value       = module.postgresql_cluster.backup_bucket
}
