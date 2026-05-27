output "namespace" {
  description = "Namespace where PostgreSQL is deployed."
  value       = local.namespace
}

output "cluster_name" {
  description = "CloudNativePG cluster name."
  value       = local.cluster_name
}

output "database" {
  description = "Application database name."
  value       = local.app_database
}

output "username" {
  description = "Application database user."
  value       = local.app_user
}

output "jdbc_url" {
  description = "JDBC URL for aof-back inside the Kubernetes cluster."
  value       = "jdbc:postgresql://${local.rw_host}:5432/${local.app_database}"
}

output "rw_host" {
  description = "Read-write PostgreSQL service host."
  value       = local.rw_host
}

output "ro_host" {
  description = "Read-only PostgreSQL service host."
  value       = local.ro_host
}

output "dump_bucket" {
  description = "S3 bucket used for manual logical dumps."
  value       = local.dump_bucket
}

output "backup_bucket" {
  description = "S3 bucket used for CloudNativePG physical backups and WAL archive."
  value       = local.backup_bucket
}

output "jenkins_job_scripts" {
  description = "Jenkins Job DSL scripts owned by this PostgreSQL module."
  value = var.enable_jenkins_database_jobs ? [
    local.dump_job_script,
    local.restore_job_script
  ] : []
}
