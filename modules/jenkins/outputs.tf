output "namespace" {
  description = "Namespace where Jenkins is installed."
  value       = kubernetes_namespace.jenkins.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.jenkins.name
}
