resource "kubernetes_namespace" "frontend" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  object_prefix = trim(var.prefix, "/")
}

resource "kubernetes_secret" "s3" {
  metadata {
    name      = "${var.name}-s3"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    access-key = var.s3_access_key
    secret-key = var.s3_secret_key
  }
}

resource "kubernetes_config_map" "proxy" {
  metadata {
    name      = "${var.name}-proxy"
    namespace = var.namespace
  }

  data = {
    "server.py" = file("${path.module}/server.py")
  }
}

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = var.name
    namespace = var.namespace

    labels = {
      app = var.name
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        labels = {
          app = var.name
        }
      }

      spec {
        container {
          name  = "proxy"
          image = "python:3.12-alpine"

          command = ["python", "/app/server.py"]

          env {
            name  = "S3_ENDPOINT"
            value = var.s3_origin
          }

          env {
            name  = "S3_REGION"
            value = var.s3_region
          }

          env {
            name  = "S3_BUCKET"
            value = var.bucket
          }

          env {
            name  = "S3_PREFIX"
            value = local.object_prefix
          }

          env {
            name = "S3_ACCESS_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3.metadata[0].name
                key  = "access-key"
              }
            }
          }

          env {
            name = "S3_SECRET_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3.metadata[0].name
                key  = "secret-key"
              }
            }
          }

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "server"
            mount_path = "/app/server.py"
            sub_path   = "server.py"
          }

          readiness_probe {
            http_get {
              path = "/nginx-health"
              port = "http"
            }
          }
        }

        volume {
          name = "server"

          config_map {
            name = kubernetes_config_map.proxy.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    selector = {
      app = var.name
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}
