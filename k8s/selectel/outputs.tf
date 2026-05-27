output "postgres_jdbc_url" {
  description = "JDBC URL for aof-back inside the Selectel Kubernetes cluster."
  value       = module.postgresql_cluster.jdbc_url
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
  description = "S3 bucket used for manual logical PostgreSQL dumps."
  value       = module.postgresql_cluster.dump_bucket
}

output "postgres_backup_bucket" {
  description = "S3 bucket used for CloudNativePG physical backups and WAL archive."
  value       = module.postgresql_cluster.backup_bucket
}

output "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is installed."
  value       = module.ingress_nginx.namespace
}

output "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed."
  value       = module.cert_manager.namespace
}

output "cloudnative_pg_operator_namespace" {
  description = "Namespace where CloudNativePG operator is installed."
  value       = module.cloudnative_pg_operator.namespace
}
