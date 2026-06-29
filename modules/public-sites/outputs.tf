output "wordpress_service_name" {
  description = "WordPress Service name."
  value       = kubernetes_service.wordpress.metadata[0].name
}

output "database_service_name" {
  description = "MariaDB Service name."
  value       = kubernetes_service.database.metadata[0].name
}

output "ingress_name" {
  description = "Ingress name."
  value       = kubernetes_ingress_v1.wordpress.metadata[0].name
}
