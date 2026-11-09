# aof-content-manager (content.zazer.fun): content editor for aof-back / aof-front
# with its own PostgreSQL. Terraform owns every object; the Jenkins job
# `aof-content-manager` only builds the image and sets it on the Deployment.
#
# Git is strictly read-only for this service (CM_GIT_READ_ONLY defaults to true
# in the image); the token in content_manager_git_token needs read access only.

locals {
  content_manager = {
    name          = "aof-content-manager"
    namespace     = "content-manager"
    db_cluster    = "content-manager-db"
    database      = "content_manager"
    workspace_pvc = "content-manager-workspace"
    secret_name   = "aof-content-manager"
    tls_secret    = "content-zazer-fun-tls"
  }

  content_manager_labels = {
    "app.kubernetes.io/name"       = local.content_manager.name
    "app.kubernetes.io/instance"   = local.content_manager.name
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace" "content_manager" {
  metadata {
    name = local.content_manager.namespace
  }
}

resource "random_password" "content_manager_db" {
  length  = 32
  special = false
}

# Translations exist only in this database, so unlike the stand databases it
# keeps both CloudNativePG physical backups (WAL archive + daily base backup,
# 14 days) and the nightly logical pg_dump to S3.
module "content_manager_db" {
  source = "../../modules/postgresql-cluster"

  name             = "content-manager"
  namespace        = kubernetes_namespace.content_manager.metadata[0].name
  cluster_name     = local.content_manager.db_cluster
  create_namespace = false

  app_database = local.content_manager.database
  app_user     = local.content_manager.database
  app_password = random_password.content_manager_db.result

  s3_endpoint_url = var.postgres_s3_endpoint_url
  s3_region       = var.postgres_s3_region
  s3_access_key   = var.postgres_s3_access_key
  s3_secret_key   = var.postgres_s3_secret_key

  postgresql_engine  = "cloudnative-pg"
  postgresql_version = "16"

  cluster_instances = 1
  storage_size      = "10Gi"
  storage_class     = "fast.ru-7a"
  wal_storage_size  = "4Gi"
  wal_storage_class = "fast.ru-7a"

  # Case-insensitive search does not work for Cyrillic in the default C locale.
  initdb_locale = "C.UTF-8"
  # Liquibase also runs CREATE EXTENSION IF NOT EXISTS; this keeps the first
  # start independent of the owner's privileges.
  post_init_application_sql = ["CREATE EXTENSION IF NOT EXISTS pg_trgm"]
  restore_database_enabled  = false

  postgres_affinity = local.database_node_affinity
  postgres_resources = {
    requests = {
      cpu    = "100m"
      memory = "512Mi"
    }
    limits = {
      memory = "1Gi"
    }
  }
  postgres_parameters = {
    max_connections = "50"
    shared_buffers  = "128MB"
  }

  enable_pooler                = false
  enable_jenkins_database_jobs = false
  logical_backup_enabled       = true

  depends_on = [
    module.cloudnative_pg_operator
  ]
}

resource "kubernetes_secret" "content_manager_registry_pull" {
  metadata {
    name      = "selectel-registry"
    namespace = kubernetes_namespace.content_manager.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.registry_server) = {
          username = var.registry_username
          password = var.registry_password
          auth     = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }
}

resource "kubernetes_secret" "content_manager" {
  metadata {
    name      = local.content_manager.secret_name
    namespace = kubernetes_namespace.content_manager.metadata[0].name
    labels    = local.content_manager_labels
  }

  type = "Opaque"

  data = {
    CM_ADMINS       = var.content_manager_admins
    CM_GIT_USERNAME = var.content_manager_git_username
    CM_GIT_TOKEN    = var.content_manager_git_token
  }

  lifecycle {
    # The admin list is maintained in the cluster (kubectl patch + pod restart);
    # content_manager_admins only seeds it when the Secret is created.
    ignore_changes = [data["CM_ADMINS"]]
  }
}

# Working copies of aof-back / aof-front (CM_WORKSPACE).
resource "kubernetes_persistent_volume_claim_v1" "content_manager_workspace" {
  metadata {
    name      = local.content_manager.workspace_pvc
    namespace = kubernetes_namespace.content_manager.metadata[0].name
    labels    = merge(local.content_manager_labels, { "app.kubernetes.io/component" = "workspace" })
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class_v1.basicssd_ru_7a.metadata[0].name

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }

  wait_until_bound = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "content_manager" {
  metadata {
    name      = local.content_manager.name
    namespace = kubernetes_namespace.content_manager.metadata[0].name
    labels    = local.content_manager_labels
  }

  spec {
    # Repository locks and the scheduled check live in process memory.
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = local.content_manager.name
        "app.kubernetes.io/instance" = local.content_manager.name
      }
    }

    template {
      metadata {
        labels = local.content_manager_labels
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret.content_manager_registry_pull.metadata[0].name
        }

        security_context {
          run_as_user            = 10001
          run_as_group           = 10001
          run_as_non_root        = true
          fs_group               = 10001
          fs_group_change_policy = "OnRootMismatch"
        }

        termination_grace_period_seconds = 60

        container {
          name              = "app"
          image             = "${var.content_manager_image_repository}:latest"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "CM_DB_URL"
            value = module.content_manager_db.jdbc_url
          }

          env {
            name = "CM_DB_USER"
            value_from {
              secret_key_ref {
                name = module.content_manager_db.app_secret_name
                key  = "username"
              }
            }
          }

          env {
            name = "CM_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = module.content_manager_db.app_secret_name
                key  = "password"
              }
            }
          }

          env {
            name  = "CM_WORKSPACE"
            value = "/data/workspace"
          }

          # Java HttpClient uses JVM proxy settings. Keep the image's memory
          # options in JAVA_TOOL_OPTIONS and native Git's direct route intact.
          env {
            name = "JDK_JAVA_OPTIONS"
            value = join(" ", [
              "-Dhttps.proxyHost=aof-agent-vpn.aof-agent-network.svc.cluster.local",
              "-Dhttps.proxyPort=8888",
              "-Dhttp.nonProxyHosts=localhost|127.*|[::1]|*.svc|*.cluster.local",
            ])
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.content_manager.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "1Gi"
            }
          }

          startup_probe {
            http_get {
              path = "/actuator/health/liveness"
              port = "http"
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 60
          }

          liveness_probe {
            http_get {
              path = "/actuator/health/liveness"
              port = "http"
            }
            period_seconds    = 20
            timeout_seconds   = 5
            failure_threshold = 3
          }

          readiness_probe {
            http_get {
              path = "/actuator/health/readiness"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 3
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/data/workspace"
          }
        }

        volume {
          name = "workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.content_manager_workspace.metadata[0].name
          }
        }
      }
    }
  }

  # The first apply runs before Jenkins has pushed an image.
  wait_for_rollout = false

  lifecycle {
    # Jenkins sets the image by digest and records the build in pod annotations.
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image,
      spec[0].template[0].metadata[0].annotations,
      metadata[0].annotations,
    ]
  }

  depends_on = [
    module.content_manager_db
  ]
}

resource "kubernetes_service_v1" "content_manager" {
  metadata {
    name      = local.content_manager.name
    namespace = kubernetes_namespace.content_manager.metadata[0].name
    labels    = local.content_manager_labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = local.content_manager.name
      "app.kubernetes.io/instance" = local.content_manager.name
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "content_manager" {
  metadata {
    name      = local.content_manager.name
    namespace = kubernetes_namespace.content_manager.metadata[0].name
    labels    = local.content_manager_labels

    annotations = {
      "cert-manager.io/cluster-issuer" = module.cert_manager.cluster_issuer_name
      # ZIP uploads of the whole xml folder (spring.servlet.multipart: 300MB).
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "300m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "300"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.content_manager_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.content_manager.metadata[0].name

              port {
                name = "http"
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [var.content_manager_host]
      secret_name = local.content_manager.tls_secret
    }
  }

  depends_on = [
    module.ingress_nginx,
    module.cert_manager
  ]
}
