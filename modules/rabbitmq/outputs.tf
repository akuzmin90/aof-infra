output "namespace" {
  value = var.namespace
}

output "service_name" {
  value = kubernetes_service.rabbitmq.metadata[0].name
}

output "host" {
  value = "${kubernetes_service.rabbitmq.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "stomp_port" {
  value = 61613
}

output "credentials_secret_name" {
  value = kubernetes_secret.rabbitmq.metadata[0].name
}

output "username_key" {
  value = "username"
}

output "password_key" {
  value = "password"
}

output "password" {
  value     = random_password.rabbitmq.result
  sensitive = true
}
