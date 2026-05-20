output "namespace" {
  description = "Namespace where ingress-nginx is installed."
  value       = kubernetes_namespace.ingress_nginx.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.ingress_nginx.name
}
