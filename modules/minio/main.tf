resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

resource "kubernetes_secret" "minio" {
  metadata {
    name      = "minio-credentials"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  data = {
    root-user     = "minioadmin"
    root-password = "minioadmin123"
  }
}

resource "kubernetes_persistent_volume_claim" "minio" {
  metadata {
    name      = "minio-data"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  wait_until_bound = false

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.minio.metadata[0].name

    labels = {
      app = "minio"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "minio"
      }
    }

    template {
      metadata {
        labels = {
          app = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "quay.io/minio/minio:latest"

          args = [
            "server",
            "/data",
            "--console-address",
            ":9001"
          ]

          env {
            name = "MINIO_ROOT_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.minio.metadata[0].name
                key  = "root-user"
              }
            }
          }

          env {
            name = "MINIO_ROOT_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.minio.metadata[0].name
                key  = "root-password"
              }
            }
          }

          port {
            name           = "api"
            container_port = 9000
          }

          port {
            name           = "console"
            container_port = 9001
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = "api"
            }
          }

          liveness_probe {
            http_get {
              path = "/minio/health/live"
              port = "api"
            }
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minio.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  spec {
    selector = {
      app = "minio"
    }

    port {
      name        = "api"
      port        = 9000
      target_port = "api"
    }

    port {
      name        = "console"
      port        = 9001
      target_port = "console"
    }
  }
}

resource "kubernetes_job_v1" "bootstrap" {
  metadata {
    name      = "minio-bootstrap"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  spec {
    backoff_limit = 6

    template {
      metadata {}

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "mc"
          image = "quay.io/minio/mc:latest"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              mc alias set local http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123
              mc mb --ignore-existing local/aof-front
              mc anonymous set download local/aof-front
            EOT
          ]
        }
      }
    }
  }

  wait_for_completion = true

  depends_on = [
    kubernetes_deployment.minio,
    kubernetes_service.minio
  ]
}
