# Staged, rollback-preserving migration of the dev PostgreSQL data volume
# from Fast to Universal v2 storage.
#
# Stages:
#   disabled  no migration resources
#   copy      create the Universal PVC and take an online physical base backup
#   replicate run the copied database as a streaming standby
#   cutover   select the promoted Universal database and scale the Fast DB to zero
#   complete  stable post-cutover state; the retained Fast PVC may be removed
#             after the rollback window

locals {
  dev_db_namespace          = local.app_instances.dev.namespace
  dev_db_cluster_name       = local.app_instances.dev.database_cluster
  dev_db_universal_name     = "${local.dev_db_cluster_name}-universal2"
  dev_db_universal_pvc_name = "${local.dev_db_universal_name}-data"
}

resource "kubernetes_persistent_volume_claim_v1" "dev_db_universal2" {
  count = local.dev_db_migration_enabled ? 1 : 0

  metadata {
    name      = local.dev_db_universal_pvc_name
    namespace = local.dev_db_namespace

    labels = {
      "app.kubernetes.io/name"       = "postgresql"
      "app.kubernetes.io/instance"   = "dev"
      "app.kubernetes.io/component"  = "universal-storage"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class_v1.universal2_ru_7a.metadata[0].name

    resources {
      requests = {
        storage = "400Gi"
      }
    }
  }

  wait_until_bound = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_job_v1" "dev_db_basebackup" {
  count = var.dev_db_storage_migration_stage == "copy" ? 1 : 0

  metadata {
    name      = "${local.dev_db_cluster_name}-basebackup-universal2"
    namespace = local.dev_db_namespace

    labels = {
      "app.kubernetes.io/name"       = "postgresql"
      "app.kubernetes.io/instance"   = "dev"
      "app.kubernetes.io/component"  = "storage-migration"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    backoff_limit = 0

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "postgresql"
          "app.kubernetes.io/instance"  = "dev"
          "app.kubernetes.io/component" = "storage-migration"
        }
      }

      spec {
        restart_policy = "Never"
        node_selector  = local.database_node_affinity.nodeSelector

        dynamic "toleration" {
          for_each = local.database_node_affinity.tolerations

          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name              = "basebackup"
          image             = "postgres:11"
          image_pull_policy = "IfNotPresent"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              set -eu
              install -d -m 0700 -o 999 -g 999 "$PGDATA"
              test ! -e "$PGDATA/PG_VERSION"
              gosu postgres pg_basebackup \
                --host="$PGHOST" \
                --port="$PGPORT" \
                --username="$PGUSER" \
                --pgdata="$PGDATA" \
                --format=plain \
                --wal-method=stream \
                --checkpoint=fast \
                --progress \
                --write-recovery-conf
              printf "\nprimary_conninfo = 'host=%s port=%s user=%s password=%s application_name=dev-universal2'\n" \
                "$PGHOST" "$PGPORT" "$PGUSER" "$PGPASSWORD" >> "$PGDATA/recovery.conf"
              chown 999:999 "$PGDATA/recovery.conf"
              chmod 0600 "$PGDATA/recovery.conf"
            EOT
          ]

          env {
            name  = "PGHOST"
            value = "${local.dev_db_cluster_name}-rw.${local.dev_db_namespace}.svc.cluster.local"
          }

          env {
            name  = "PGPORT"
            value = "5432"
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env {
            name = "PGUSER"
            value_from {
              secret_key_ref {
                name = module.postgresql_cluster["dev"].app_secret_name
                key  = "username"
              }
            }
          }

          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = module.postgresql_cluster["dev"].app_secret_name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.dev_db_universal2[0].metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = false
}

resource "kubernetes_service_v1" "dev_db_universal2" {
  count = local.dev_db_migration_enabled ? 1 : 0

  metadata {
    name      = local.dev_db_universal_name
    namespace = local.dev_db_namespace

    labels = {
      "app.kubernetes.io/name"      = "postgresql"
      "app.kubernetes.io/instance"  = "dev"
      "app.kubernetes.io/component" = "universal-primary"
    }
  }

  spec {
    port {
      name        = "postgresql"
      port        = 5432
      target_port = "postgresql"
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name"      = "postgresql"
      "app.kubernetes.io/instance"  = "dev"
      "app.kubernetes.io/component" = "universal-primary"
    }
  }
}

resource "kubernetes_stateful_set_v1" "dev_db_universal2" {
  count = local.dev_db_migration_enabled ? 1 : 0

  metadata {
    name      = local.dev_db_universal_name
    namespace = local.dev_db_namespace

    labels = {
      "app.kubernetes.io/name"      = "postgresql"
      "app.kubernetes.io/instance"  = "dev"
      "app.kubernetes.io/component" = "universal-primary"
      app                           = "postgresql"
    }
  }

  spec {
    replicas              = local.dev_db_new_running ? 1 : 0
    service_name          = kubernetes_service_v1.dev_db_universal2[0].metadata[0].name
    pod_management_policy = "OrderedReady"

    selector {
      match_labels = {
        "app.kubernetes.io/name"      = "postgresql"
        "app.kubernetes.io/instance"  = "dev"
        "app.kubernetes.io/component" = "universal-primary"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "postgresql"
          "app.kubernetes.io/instance"  = "dev"
          "app.kubernetes.io/component" = "universal-primary"
          app                           = "postgresql"
        }
      }

      spec {
        node_selector = local.database_node_affinity.nodeSelector

        dynamic "toleration" {
          for_each = local.database_node_affinity.tolerations

          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name              = "postgres"
          image             = "postgres:11"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "postgresql"
            container_port = 5432
            protocol       = "TCP"
          }

          args = [
            "-c",
            "max_connections=${local.small_postgres_parameters.max_connections}",
            "-c",
            "shared_buffers=${local.small_postgres_parameters.shared_buffers}",
            "-c",
            "synchronous_commit=${local.small_postgres_parameters.synchronous_commit}",
            "-c",
            "listen_addresses=*",
          ]

          env {
            name  = "POSTGRES_DB"
            value = "aof"
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = module.postgresql_cluster["dev"].app_secret_name
                key  = "username"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = module.postgresql_cluster["dev"].app_secret_name
                key  = "password"
              }
            }
          }

          startup_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 60
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            period_seconds    = 20
            timeout_seconds   = 5
            failure_threshold = 6
          }

          resources {
            requests = local.small_postgres_resources.requests
            limits   = local.small_postgres_resources.limits
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.dev_db_universal2[0].metadata[0].name
          }
        }
      }
    }
  }
}
