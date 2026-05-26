output "namespace" {
  value = "aof"
}

output "service_name" {
  value = kubernetes_service.ignite.metadata[0].name
}

output "discovery_address" {
  value = "${kubernetes_service.ignite.metadata[0].name}.aof.svc.cluster.local:47500"
}
