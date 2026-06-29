locals {
  labels = {
    "app.kubernetes.io/name"       = "public-sites"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/managed-by" = "terraform"
  }

  db_labels = merge(local.labels, {
    "app.kubernetes.io/component" = "mariadb"
  })

  wordpress_labels = merge(local.labels, {
    "app.kubernetes.io/component" = "wordpress"
  })

  db_name = "wordpress"
  db_user = "wordpress"

  restore_enabled = var.restore_generation > 0
  tls_secret_name = "${var.name}-tls"
}

resource "kubernetes_secret" "database" {
  metadata {
    name      = "${var.name}-db"
    namespace = var.namespace

    labels = local.labels
  }

  type = "Opaque"

  data = {
    database      = local.db_name
    username      = local.db_user
    password      = var.db_password
    root-password = var.db_root_password
  }
}

resource "kubernetes_persistent_volume_claim" "files" {
  metadata {
    name      = "${var.name}-files"
    namespace = var.namespace

    labels = local.wordpress_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast.ru-7a"

    resources {
      requests = {
        storage = var.files_size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "database" {
  metadata {
    name      = "${var.name}-db"
    namespace = var.namespace

    labels = local.db_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast.ru-7a"

    resources {
      requests = {
        storage = var.db_size
      }
    }
  }
}

resource "kubernetes_service" "database" {
  metadata {
    name      = "${var.name}-db"
    namespace = var.namespace

    labels = local.db_labels
  }

  spec {
    selector = local.db_labels

    port {
      name        = "mysql"
      port        = 3306
      target_port = "mysql"
    }
  }
}

resource "kubernetes_stateful_set" "database" {
  metadata {
    name      = "${var.name}-db"
    namespace = var.namespace

    labels = local.db_labels
  }

  spec {
    service_name = kubernetes_service.database.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.db_labels
    }

    template {
      metadata {
        labels = local.db_labels
      }

      spec {
        container {
          name              = "mariadb"
          image             = "mariadb:10.6.4-focal"
          image_pull_policy = "IfNotPresent"
          args              = ["--default-authentication-plugin=mysql_native_password"]

          port {
            name           = "mysql"
            container_port = 3306
          }

          env {
            name = "MYSQL_DATABASE"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "database"
              }
            }
          }

          env {
            name = "MYSQL_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "MYSQL_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "MYSQL_ROOT_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "root-password"
              }
            }
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "mysqladmin ping -h 127.0.0.1 -uroot -p$MYSQL_ROOT_PASSWORD"]
            }

            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 12
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "mysqladmin ping -h 127.0.0.1 -uroot -p$MYSQL_ROOT_PASSWORD"]
            }

            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 6
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }

            limits = {
              cpu    = "1"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/mysql"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.database.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "wordpress" {
  metadata {
    name      = "${var.name}-wordpress"
    namespace = var.namespace

    labels = local.wordpress_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.wordpress_labels
    }

    template {
      metadata {
        labels = local.wordpress_labels
      }

      spec {
        container {
          name              = "wordpress"
          image             = "wordpress:latest"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 80
          }

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "${kubernetes_service.database.metadata[0].name}.${var.namespace}.svc.cluster.local"
          }

          env {
            name = "WORDPRESS_DB_NAME"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "database"
              }
            }
          }

          env {
            name = "WORDPRESS_DB_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "WORDPRESS_DB_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "password"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 12
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "files"
            mount_path = "/var/www/html"
          }
        }

        volume {
          name = "files"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.files.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_stateful_set.database,
    kubernetes_job_v1.restore_files,
    kubernetes_job_v1.restore_database
  ]
}

resource "kubernetes_service" "wordpress" {
  metadata {
    name      = "${var.name}-wordpress"
    namespace = var.namespace

    labels = local.wordpress_labels
  }

  spec {
    selector = local.wordpress_labels

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "wordpress" {
  metadata {
    name      = "${var.name}-wordpress"
    namespace = var.namespace

    labels = local.wordpress_labels

    annotations = merge({
      "nginx.ingress.kubernetes.io/proxy-body-size" = "128m"
      "nginx.ingress.kubernetes.io/ssl-redirect"    = var.tls_enabled ? "true" : "false"
      }, var.tls_enabled ? {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer_name
    } : {})
  }

  spec {
    ingress_class_name = "nginx"

    dynamic "rule" {
      for_each = toset(var.hosts)

      content {
        host = rule.value

        http {
          path {
            path      = "/"
            path_type = "Prefix"

            backend {
              service {
                name = kubernetes_service.wordpress.metadata[0].name

                port {
                  number = 80
                }
              }
            }
          }
        }
      }
    }

    dynamic "tls" {
      for_each = var.tls_enabled ? [1] : []

      content {
        hosts       = var.hosts
        secret_name = local.tls_secret_name
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "backup_to_s3" {
  metadata {
    name      = "${var.name}-backup-to-s3"
    namespace = var.namespace

    labels = merge(local.labels, {
      "app.kubernetes.io/component" = "backup"
    })
  }

  spec {
    schedule                      = "0 3 * * *"
    timezone                      = "Europe/Moscow"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/component" = "backup"
        })
      }

      spec {
        backoff_limit              = 1
        ttl_seconds_after_finished = 604800

        template {
          metadata {
            labels = merge(local.labels, {
              "app.kubernetes.io/component" = "backup"
            })
          }

          spec {
            restart_policy = "Never"

            affinity {
              pod_affinity {
                required_during_scheduling_ignored_during_execution {
                  topology_key = "kubernetes.io/hostname"

                  label_selector {
                    match_labels = local.wordpress_labels
                  }
                }
              }
            }

            init_container {
              name              = "archive-files"
              image             = "alpine:3.20"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                "set -eu; tar -czf /work/files.tar.gz -C /wordpress .; tar -tzf /work/files.tar.gz >/dev/null"
              ]

              volume_mount {
                name       = "files"
                mount_path = "/wordpress"
                read_only  = true
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }

            init_container {
              name              = "dump-database"
              image             = "mariadb:10.6.4-focal"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                "set -eu; mysqldump --single-transaction --quick --lock-tables=false --no-tablespaces -h ${kubernetes_service.database.metadata[0].name} -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\" | gzip > /work/db.sql.gz; gzip -t /work/db.sql.gz"
              ]

              env {
                name = "MYSQL_DATABASE"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "database"
                  }
                }
              }

              env {
                name = "MYSQL_USER"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "username"
                  }
                }
              }

              env {
                name = "MYSQL_PASSWORD"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "password"
                  }
                }
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }

            container {
              name              = "upload-backup"
              image             = "minio/mc:latest"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                "set -eu; TS=$(TZ=Europe/Moscow date +%Y%m%d-%H%M%S); cat > /work/restore-info.txt <<EOF\nsite=${var.backup_s3_site_prefix}\ntype=kubernetes\nnamespace=${var.namespace}\nwordpress_deployment=${kubernetes_deployment.wordpress.metadata[0].name}\ndb_service=${kubernetes_service.database.metadata[0].name}\ndb_name=${local.db_name}\ncreated_at=$TS\nEOF\nmc alias set backup \"$AWS_ENDPOINT_URL\" \"$AWS_ACCESS_KEY_ID\" \"$AWS_SECRET_ACCESS_KEY\" --api S3v4 --path on; mc cp /work/db.sql.gz \"backup/$BUCKET/${var.backup_s3_site_prefix}/$TS/db.sql.gz\"; mc cp /work/files.tar.gz \"backup/$BUCKET/${var.backup_s3_site_prefix}/$TS/files.tar.gz\"; mc cp /work/restore-info.txt \"backup/$BUCKET/${var.backup_s3_site_prefix}/$TS/restore-info.txt\""
              ]

              env_from {
                secret_ref {
                  name = "public-sites-backup-s3"
                }
              }

              env {
                name = "BUCKET"

                value_from {
                  secret_key_ref {
                    name = "public-sites-backup-s3"
                    key  = "bucket"
                  }
                }
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }

            volume {
              name = "work"

              empty_dir {}
            }

            volume {
              name = "files"

              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.files.metadata[0].name
                read_only  = true
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.wordpress,
    kubernetes_stateful_set.database
  ]
}

resource "kubernetes_cron_job_v1" "restore_from_s3" {
  count = var.restore_s3_backup_path == null ? 0 : 1

  metadata {
    name      = "${var.name}-restore-from-s3"
    namespace = var.namespace

    labels = merge(local.labels, {
      "app.kubernetes.io/component" = "restore"
    })
  }

  spec {
    schedule                      = "0 3 * * *"
    suspend                       = true
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/component" = "restore"
        })
      }

      spec {
        backoff_limit              = 1
        ttl_seconds_after_finished = 86400

        template {
          metadata {
            labels = merge(local.labels, {
              "app.kubernetes.io/component" = "restore"
            })
          }

          spec {
            restart_policy = "Never"

            init_container {
              name              = "download-backup"
              image             = "minio/mc:latest"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                "set -eu; mc alias set backup \"$AWS_ENDPOINT_URL\" \"$AWS_ACCESS_KEY_ID\" \"$AWS_SECRET_ACCESS_KEY\" --api S3v4 --path on; mc cp \"backup/$BUCKET/${var.restore_s3_backup_path}/files.tar.gz\" /work/files.tar.gz; mc cp \"backup/$BUCKET/${var.restore_s3_backup_path}/db.sql.gz\" /work/db.sql.gz; mc cp \"backup/$BUCKET/${var.restore_s3_backup_path}/restore-info.txt\" /work/restore-info.txt || true"
              ]

              env_from {
                secret_ref {
                  name = "public-sites-backup-s3"
                }
              }

              env {
                name = "BUCKET"

                value_from {
                  secret_key_ref {
                    name = "public-sites-backup-s3"
                    key  = "bucket"
                  }
                }
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
              }
            }

            init_container {
              name              = "restore-files"
              image             = "wordpress:latest"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                <<-EOT
                set -eu
                rm -rf /tmp/extract
                mkdir -p /tmp/extract
                tar -xzf /work/files.tar.gz -C /tmp/extract
                find /restore-target -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                if [ -f /tmp/extract/wp-config.php ]; then
                  cp -a /tmp/extract/. /restore-target/
                else
                  first=$(find /tmp/extract -mindepth 1 -maxdepth 1 -type d | head -n 1)
                  if [ -n "$first" ] && [ -f "$first/wp-config.php" ]; then
                    cp -a "$first"/. /restore-target/
                  else
                    cp -a /tmp/extract/. /restore-target/
                  fi
                fi
                cat > /tmp/fix-wp-config.php <<'PHP'
                <?php
                $file = '/restore-target/wp-config.php';
                $content = file_get_contents($file);

                $proxySnippet = <<<'SNIPPET'
                if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
                    $_SERVER['HTTPS'] = 'on';
                }

                SNIPPET;

                if (strpos($content, 'HTTP_X_FORWARDED_PROTO') === false) {
                    $content = preg_replace('/<\?php\s*/', "<?php\n" . $proxySnippet, $content, 1);
                }

                $values = [
                    'DB_NAME' => getenv('WORDPRESS_DB_NAME'),
                    'DB_USER' => getenv('WORDPRESS_DB_USER'),
                    'DB_PASSWORD' => getenv('WORDPRESS_DB_PASSWORD'),
                    'DB_HOST' => getenv('WORDPRESS_DB_HOST'),
                ];

                foreach ($values as $key => $value) {
                    if ($value === false || $value === '') {
                        fwrite(STDERR, "Missing {$key}\n");
                        exit(1);
                    }

                    $replacement = "define( '{$key}', '" . addcslashes($value, "\\'") . "' );";
                    $content = preg_replace(
                        "/define\s*\(\s*['\"]{$key}['\"]\s*,\s*['\"][^'\"]*['\"]\s*\);/",
                        $replacement,
                        $content,
                        1
                    );
                }

                file_put_contents($file, $content);
                PHP
                php /tmp/fix-wp-config.php
                if [ ! -f /restore-target/.htaccess ]; then
                  cat > /restore-target/.htaccess <<'HTACCESS'
                # BEGIN WordPress
                <IfModule mod_rewrite.c>
                RewriteEngine On
                RewriteRule ^wp-config\.php.*$ - [F,L]
                RewriteRule ^info\.php$ - [F,L]
                RewriteRule ^privacy$ /assets/policy.html [L]
                RewriteRule ^agreement$ /assets/agreement.html [L]
                RewriteRule ^privacy_policy$ /assets/privacy_policy.html [L]
                RewriteRule ^terms_of_use$ /assets/terms_of_use.html [L]
                RewriteRule ^[Aa]pp-ads\.txt$ /assets/ads2.html [L]
                RewriteRule ^acc_del$ /assets/acc_del.html [L]
                RewriteRule ^user_agreement$ /assets/beeline.html [L]
                RewriteRule .* - [E=HTTP_AUTHORIZATION:%%{HTTP:Authorization}]
                RewriteBase /
                RewriteRule ^index\.php$ - [L]
                RewriteCond %%{REQUEST_FILENAME} !-f
                RewriteCond %%{REQUEST_FILENAME} !-d
                RewriteRule . /index.php [L]
                </IfModule>
                # END WordPress
                HTACCESS
                fi
                chown -R 33:33 /restore-target
                EOT
              ]

              env {
                name  = "WORDPRESS_DB_HOST"
                value = "${kubernetes_service.database.metadata[0].name}.${var.namespace}.svc.cluster.local"
              }

              env {
                name = "WORDPRESS_DB_NAME"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "database"
                  }
                }
              }

              env {
                name = "WORDPRESS_DB_USER"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "username"
                  }
                }
              }

              env {
                name = "WORDPRESS_DB_PASSWORD"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "password"
                  }
                }
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
                read_only  = true
              }

              volume_mount {
                name       = "files"
                mount_path = "/restore-target"
              }
            }

            init_container {
              name              = "restore-database"
              image             = "mariadb:10.6.4-focal"
              image_pull_policy = "IfNotPresent"
              command = [
                "sh",
                "-c",
                "set -eu; mysql -h ${kubernetes_service.database.metadata[0].name} -uroot -p\"$MYSQL_ROOT_PASSWORD\" -e \"DROP DATABASE IF EXISTS \\`$MYSQL_DATABASE\\`; CREATE DATABASE \\`$MYSQL_DATABASE\\`;\"; gzip -dc /work/db.sql.gz | tail -n +2 | mysql -h ${kubernetes_service.database.metadata[0].name} -uroot -p\"$MYSQL_ROOT_PASSWORD\" \"$MYSQL_DATABASE\""
              ]

              env {
                name = "MYSQL_DATABASE"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "database"
                  }
                }
              }

              env {
                name = "MYSQL_ROOT_PASSWORD"

                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.database.metadata[0].name
                    key  = "root-password"
                  }
                }
              }

              volume_mount {
                name       = "work"
                mount_path = "/work"
                read_only  = true
              }
            }

            container {
              name              = "done"
              image             = "alpine:3.20"
              image_pull_policy = "IfNotPresent"
              command           = ["sh", "-c", "echo restore complete"]
            }

            volume {
              name = "work"

              empty_dir {}
            }

            volume {
              name = "files"

              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.files.metadata[0].name
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_stateful_set.database,
    kubernetes_persistent_volume_claim.files
  ]
}

resource "kubernetes_job_v1" "restore_files" {
  count = local.restore_enabled ? 1 : 0

  metadata {
    name      = "${var.name}-restore-files-${var.restore_generation}"
    namespace = var.namespace

    labels = local.wordpress_labels
  }

  spec {
    template {
      metadata {
        labels = local.wordpress_labels
      }

      spec {
        restart_policy = "Never"

        container {
          name              = "restore"
          image             = "alpine:3.20"
          image_pull_policy = "IfNotPresent"
          command = [
            "sh",
            "-c",
            "set -eu; test -f /backup/${var.restore_backup_path}/files.tar.gz; find /restore-target -mindepth 1 -maxdepth 1 -exec rm -rf {} +; tar -xzf /backup/${var.restore_backup_path}/files.tar.gz -C /restore-target --strip-components=${var.restore_strip_components}; chown -R 33:33 /restore-target"
          ]

          volume_mount {
            name       = "files"
            mount_path = "/restore-target"
          }

          volume_mount {
            name       = "backup"
            mount_path = "/backup"
            read_only  = true
          }
        }

        volume {
          name = "files"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.files.metadata[0].name
          }
        }

        volume {
          name = "backup"

          persistent_volume_claim {
            claim_name = var.restore_backup_pvc_name
          }
        }
      }
    }

    backoff_limit = 1
  }

  wait_for_completion = true

  lifecycle {
    precondition {
      condition     = !local.restore_enabled || (var.restore_backup_pvc_name != null && var.restore_backup_path != null)
      error_message = "restore_backup_pvc_name and restore_backup_path are required when restore_generation is greater than 0."
    }
  }
}

resource "kubernetes_job_v1" "restore_database" {
  count = local.restore_enabled ? 1 : 0

  metadata {
    name      = "${var.name}-restore-db-${var.restore_generation}"
    namespace = var.namespace

    labels = local.db_labels
  }

  spec {
    template {
      metadata {
        labels = local.db_labels
      }

      spec {
        restart_policy = "Never"

        container {
          name              = "restore"
          image             = "mariadb:10.6.4-focal"
          image_pull_policy = "IfNotPresent"
          command = [
            "sh",
            "-c",
            "set -eu; test -f /backup/${var.restore_backup_path}/db.sql.gz; gzip -dc /backup/${var.restore_backup_path}/db.sql.gz | mysql -h ${kubernetes_service.database.metadata[0].name} -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\""
          ]

          env {
            name = "MYSQL_DATABASE"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "database"
              }
            }
          }

          env {
            name = "MYSQL_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "MYSQL_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.database.metadata[0].name
                key  = "password"
              }
            }
          }

          volume_mount {
            name       = "backup"
            mount_path = "/backup"
            read_only  = true
          }
        }

        volume {
          name = "backup"

          persistent_volume_claim {
            claim_name = var.restore_backup_pvc_name
          }
        }
      }
    }

    backoff_limit = 1
  }

  wait_for_completion = true

  depends_on = [
    kubernetes_stateful_set.database,
    kubernetes_job_v1.restore_files
  ]

  lifecycle {
    precondition {
      condition     = !local.restore_enabled || (var.restore_backup_pvc_name != null && var.restore_backup_path != null)
      error_message = "restore_backup_pvc_name and restore_backup_path are required when restore_generation is greater than 0."
    }
  }
}
