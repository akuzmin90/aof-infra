output "namespace" {
  description = "Namespace where the frontend gateway is installed."
  value       = var.namespace
}

output "service_name" {
  description = "Frontend gateway Kubernetes service name."
  value       = kubernetes_service.frontend.metadata[0].name
}
