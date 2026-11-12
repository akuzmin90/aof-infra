output "namespace" {
  value = kubernetes_namespace_v1.agent.metadata[0].name
}

output "runtime_image_digest" {
  value = local.image_digest
}

output "releases" {
  value = { for name, release in helm_release.agent : name => release.name }
}
