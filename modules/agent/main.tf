resource "kubernetes_namespace_v1" "agent" {
  metadata {
    name = "aof-agent"
    labels = {
      "app.kubernetes.io/part-of"   = "aof-agent"
      "kubernetes.io/metadata.name" = "aof-agent"
    }
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [metadata[0].annotations]
  }
}

resource "kubernetes_resource_quota_v1" "agent" {
  metadata {
    name      = "agent-budget"
    namespace = kubernetes_namespace_v1.agent.metadata[0].name
  }
  spec {
    hard = {
      pods                   = "5"
      "requests.cpu"         = "2"
      "requests.memory"      = "4Gi"
      "limits.cpu"           = "5"
      "limits.memory"        = "7Gi"
      "requests.storage"     = "20Gi"
      persistentvolumeclaims = "5"
    }
  }
}

resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace_v1.agent.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

data "kubernetes_resources" "runtime" {
  api_version    = "apps/v1"
  kind           = "Deployment"
  namespace      = kubernetes_namespace_v1.agent.metadata[0].name
  field_selector = "metadata.name=aof-agent-telegram"
}

locals {
  running_digest = try(split("@", data.kubernetes_resources.runtime.objects[0].spec.template.spec.containers[0].image)[1], null)
  image_digest   = coalesce(var.image_digest, local.running_digest, yamldecode(file("${path.module}/../../k8s/agent-telegram/values.yaml")).image.digest)
  releases = {
    telegram  = { name = "aof-agent-telegram", chart = "${path.module}/../../k8s/agent-telegram" }
    coding    = { name = "aof-agent-coding", chart = "${path.module}/../../k8s/agent-coding" }
    database  = { name = "aof-agent-db", chart = "${path.module}/../../k8s/agent-database" }
    workspace = { name = "aof-agent-workspace", chart = "${path.module}/../../k8s/agent-workspace" }
    worker    = { name = "aof-agent-worker", chart = "${path.module}/../../k8s/agent-worker" }
  }
}

resource "helm_release" "agent" {
  for_each         = local.releases
  name             = each.value.name
  namespace        = kubernetes_namespace_v1.agent.metadata[0].name
  chart            = each.value.chart
  create_namespace = false
  wait             = true
  timeout          = 360
  atomic           = true
  cleanup_on_fail  = true

  values = concat(
    [file("${each.value.chart}/values.yaml")],
    each.key == "telegram" ? [yamlencode({ image = { digest = local.image_digest }, engine = { digest = local.image_digest } })] : [],
    each.key == "coding" ? [yamlencode({ image = { digest = local.image_digest } })] : [],
    each.key == "worker" ? [file("${path.module}/../../k8s/agent-worker/login-values.yaml"), yamlencode({ replicas = 0 })] : []
  )

  lifecycle {
    prevent_destroy = true
  }
}
