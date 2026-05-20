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
  description = "Selectel Managed Kubernetes test cluster ID."
  value       = selectel_mks_cluster_v1.test.id
}

output "k8s_cluster_name" {
  description = "Selectel Managed Kubernetes test cluster name."
  value       = selectel_mks_cluster_v1.test.name
}

output "k8s_cluster_region" {
  description = "Selectel Managed Kubernetes test cluster region."
  value       = selectel_mks_cluster_v1.test.region
}

output "k8s_kubeconfig" {
  description = "Kubeconfig for the test cluster."
  value       = data.selectel_mks_kubeconfig_v1.test.raw_config
  sensitive   = true
}

output "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is installed."
  value       = module.ingress_nginx.namespace
}

output "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed."
  value       = module.cert_manager.namespace
}

output "jenkins_namespace" {
  description = "Namespace where Jenkins is installed."
  value       = module.jenkins.namespace
}
