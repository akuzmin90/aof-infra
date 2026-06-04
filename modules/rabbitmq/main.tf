resource "kubernetes_namespace" "rabbitmq" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "rabbitmq" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    username = "aof"
    password = random_password.rabbitmq.result
  }
}

resource "kubernetes_config_map" "rabbitmq" {
  metadata {
    name      = "rabbitmq-config"
    namespace = var.namespace
  }

  data = {
    enabled_plugins = "[rabbitmq_management,rabbitmq_stomp]."
  }
}

resource "kubernetes_deployment" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = var.namespace

    labels = {
      app = "rabbitmq"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "rabbitmq"
      }
    }

    template {
      metadata {
        labels = {
          app = "rabbitmq"
        }
      }

      spec {
        container {
          name              = "rabbitmq"
          image             = "rabbitmq:3.13-management"
          image_pull_policy = "IfNotPresent"

          env {
            name = "RABBITMQ_DEFAULT_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.rabbitmq.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "RABBITMQ_DEFAULT_PASS"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.rabbitmq.metadata[0].name
                key  = "password"
              }
            }
          }

          port {
            name           = "amqp"
            container_port = 5672
          }

          port {
            name           = "stomp"
            container_port = 61613
          }

          port {
            name           = "management"
            container_port = 15672
          }

          readiness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "check_port_connectivity"]
            }

            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          liveness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "ping"]
            }

            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              cpu    = "1"
              memory = "768Mi"
            }
          }

          volume_mount {
            name       = "enabled-plugins"
            mount_path = "/etc/rabbitmq/enabled_plugins"
            sub_path   = "enabled_plugins"
            read_only  = true
          }
        }

        volume {
          name = "enabled-plugins"

          config_map {
            name = kubernetes_config_map.rabbitmq.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "rabbitmq"
    }

    port {
      name        = "amqp"
      port        = 5672
      target_port = "amqp"
    }

    port {
      name        = "stomp"
      port        = 61613
      target_port = "stomp"
    }

    port {
      name        = "management"
      port        = 15672
      target_port = "management"
    }
  }
}
