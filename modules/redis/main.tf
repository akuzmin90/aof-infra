resource "kubernetes_namespace" "redis" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace

    labels = {
      app = "redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        container {
          name              = "redis"
          image             = "redis:7"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "redis"
            container_port = 6379
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }

            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }

            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 6
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = "redis"
    }
  }
}
