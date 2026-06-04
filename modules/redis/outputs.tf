output "namespace" {
  value = var.namespace
}

output "service_name" {
  value = kubernetes_service.redis.metadata[0].name
}

output "host" {
  value = "${kubernetes_service.redis.metadata[0].name}.${var.namespace}.svc.cluster.local"
}
