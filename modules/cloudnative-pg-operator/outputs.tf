output "namespace" {
  description = "Namespace where the CloudNativePG operator is installed."
  value       = kubernetes_namespace.cloudnative_pg.metadata[0].name
}

output "release_name" {
  description = "CloudNativePG Helm release name."
  value       = helm_release.cloudnative_pg.name
}
