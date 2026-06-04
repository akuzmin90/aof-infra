output "namespace" {
  value = var.namespace
}

output "service_name" {
  value = kubernetes_service.ignite.metadata[0].name
}

output "discovery_address" {
  value = "${kubernetes_service.ignite.metadata[0].name}.${var.namespace}.svc.cluster.local:47500"
}
