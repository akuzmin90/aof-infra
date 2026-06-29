output "registry_id" {
  description = "Selectel Container Registry ID."
  value       = selectel_craas_registry_v1.main.id
}

output "registry_name" {
  description = "Selectel Container Registry name."
  value       = selectel_craas_registry_v1.main.name
}

output "registry_endpoint" {
  description = "Selectel Container Registry Docker endpoint."
  value       = "cr.selcloud.ru"
}

output "registry_push_prefix" {
  description = "Prefix to use when tagging Docker images before push."
  value       = "cr.selcloud.ru/${selectel_craas_registry_v1.main.name}"
}

output "registry_username" {
  description = "Username for Docker login."
  value       = selectel_craas_token_v2.registry_rw.username
  sensitive   = true
}

output "registry_token" {
  description = "Token for Docker login."
  value       = selectel_craas_token_v2.registry_rw.token
  sensitive   = true
}

output "k8s_cluster_id" {
  description = "Selectel Managed Kubernetes cluster ID."
  value       = selectel_mks_cluster_v1.main.id
}

output "k8s_cluster_name" {
  description = "Selectel Managed Kubernetes cluster name."
  value       = selectel_mks_cluster_v1.main.name
}

output "k8s_cluster_region" {
  description = "Selectel Managed Kubernetes cluster region."
  value       = selectel_mks_cluster_v1.main.region
}

output "k8s_compute_nodegroup_id" {
  description = "App node group ID."
  value       = selectel_mks_nodegroup_v1.compute.id
}

output "k8s_database_nodegroup_id" {
  description = "Database node group ID."
  value       = selectel_mks_nodegroup_v1.database.id
}

output "k8s_kubeconfig" {
  description = "Kubeconfig for the cluster."
  value       = data.selectel_mks_kubeconfig_v1.main.raw_config
  sensitive   = true
}

output "frontend_s3_endpoint_url" {
  description = "Selectel S3 endpoint for frontend uploads."
  value       = "https://s3.ru-7.storage.selcloud.ru"
}

output "frontend_s3_region" {
  description = "Selectel S3 region for frontend uploads."
  value       = "ru-7"
}

output "frontend_s3_buckets" {
  description = "Per-instance buckets used for frontend static assets."
  value = {
    for instance, bucket in openstack_objectstorage_container_v1.frontend_instance : instance => bucket.name
  }
}

output "observability_loki_s3_endpoint_url" {
  description = "Selectel S3 endpoint used by Loki."
  value       = "https://s3.ru-7.storage.selcloud.ru"
}

output "observability_loki_s3_region" {
  description = "Selectel S3 region used by Loki."
  value       = "ru-7"
}

output "observability_loki_s3_bucket" {
  description = "S3 bucket used by Loki for durable log storage."
  value       = openstack_objectstorage_container_v1.observability_loki_logs.name
}
