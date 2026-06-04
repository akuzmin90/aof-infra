output "postgres_jdbc_url" {
  description = "JDBC URLs for aof-back instances inside the Selectel Kubernetes cluster."
  value = {
    for name, database in module.postgresql_cluster : name => database.jdbc_url
  }
}

output "postgres_username" {
  description = "PostgreSQL application usernames by instance."
  value = {
    for name, database in module.postgresql_cluster : name => database.username
  }
}

output "postgres_password" {
  description = "Generated PostgreSQL application passwords by instance."
  value = {
    for name, password in random_password.postgres_app : name => password.result
  }
  sensitive = true
}

output "postgres_dump_bucket" {
  description = "S3 bucket used for manual logical PostgreSQL dumps."
  value       = values(module.postgresql_cluster)[0].dump_bucket
}

output "postgres_backup_bucket" {
  description = "S3 bucket used for CloudNativePG physical backups and WAL archive."
  value       = values(module.postgresql_cluster)[0].backup_bucket
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

output "jenkins_namespace" {
  description = "Namespace where Jenkins is installed."
  value       = module.jenkins.namespace
}

output "jenkins_admin_username" {
  description = "Initial Jenkins admin username."
  value       = "admin"
}

output "jenkins_admin_password" {
  description = "Initial Jenkins admin password."
  value       = random_password.jenkins_admin.result
  sensitive   = true
}

output "jenkins_host" {
  description = "Jenkins ingress host."
  value       = var.jenkins_host
}

output "aof_back_hosts" {
  description = "Per-instance aof-back ingress hosts."
  value = {
    for name in keys(local.app_instances) : name => "${name}.${var.app_domain_suffix}"
  }
}
