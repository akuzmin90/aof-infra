output "namespace" {
  value = "aof"
}

output "service_name" {
  value = kubernetes_service.redis.metadata[0].name
}

output "host" {
  value = "${kubernetes_service.redis.metadata[0].name}.aof.svc.cluster.local"
}
