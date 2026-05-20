output "namespace" {
  description = "Namespace where Argo CD is installed."
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.argocd.name
}
