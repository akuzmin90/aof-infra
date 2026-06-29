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

output "public_sites_namespace" {
  description = "Namespace for public legacy websites."
  value       = var.public_sites_enabled ? local.public_sites_namespace : null
}

output "public_sites_ingresses" {
  description = "Public legacy website ingress names."
  value = var.public_sites_enabled ? {
    for name, site in module.public_sites : name => site.ingress_name
  } : {}
}

output "public_sites_backup_s3_endpoint_url" {
  description = "S3 endpoint for public sites backups."
  value       = local.public_sites_backup_s3.endpoint_url
}

output "public_sites_backup_s3_region" {
  description = "S3 region for public sites backups."
  value       = local.public_sites_backup_s3.region
}

output "public_sites_backup_s3_bucket" {
  description = "S3 bucket for public sites backups."
  value       = openstack_objectstorage_container_v1.public_sites_backups.name
}

output "public_sites_backup_s3_secret_name" {
  description = "Kubernetes Secret in public-sites containing backup S3 credentials."
  value       = var.public_sites_enabled ? kubernetes_secret.public_sites_backup_s3[0].metadata[0].name : null
}

output "public_sites_backup_s3_access_key" {
  description = "S3 access key for public sites backups."
  value       = var.public_sites_backup_s3_access_key
  sensitive   = true
}

output "public_sites_backup_s3_secret_key" {
  description = "S3 secret key for public sites backups."
  value       = var.public_sites_backup_s3_secret_key
  sensitive   = true
}

output "observability_namespace" {
  description = "Namespace where Grafana, Loki, and Alloy are deployed."
  value       = module.observability.namespace
}

output "observability_loki_bucket" {
  description = "S3 bucket used by Loki."
  value       = var.observability_loki_s3_bucket
}

output "dedicated_logs_push_url" {
  description = "Authenticated Loki-compatible push endpoint for dedicated server Alloy agents."
  value       = "https://grafana.${var.app_domain_suffix}/loki/api/v1/push"
}

output "dedicated_logs_basic_auth_username" {
  description = "Basic auth username for dedicated server Alloy agents."
  value       = "alloy"
}

output "dedicated_logs_basic_auth_password" {
  description = "Basic auth password for dedicated server Alloy agents."
  value       = random_password.dedicated_logs_basic_auth.result
  sensitive   = true
}

output "grafana_admin_username" {
  description = "Grafana admin username."
  value       = module.observability.grafana_admin_username
}

output "grafana_admin_password" {
  description = "Grafana admin password."
  value       = module.observability.grafana_admin_password
  sensitive   = true
}
