locals {
  namespace             = "database"
  cluster_name          = "aof-db"
  app_database          = "aof"
  app_user              = "aof"
  app_secret_name       = "aof-db-app"
  backup_bucket         = "aof-postgres-backups"
  dump_bucket           = "aof-postgres-dumps"
  backup_path           = "physical"
  dump_path             = "manual"
  rw_host               = "${local.cluster_name}-rw.${local.namespace}.svc.cluster.local"
  ro_host               = "${local.cluster_name}-ro.${local.namespace}.svc.cluster.local"
  s3_credentials_secret = "aof-postgres-s3"
  dump_job_script       = <<-EOT
    pipelineJob('aof-db-dump-manual') {
      description('Creates a manual logical PostgreSQL dump with pg_dump -Fc and uploads it to the configured S3-compatible bucket.')
      keepDependencies(false)
      parameters {
        stringParam('DATABASE', '${local.app_database}', 'Database to dump.')
        stringParam('DUMP_LABEL', 'manual', 'Label included in the dump object name.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            podTemplate(namespace: '${local.namespace}', yaml: """
            apiVersion: v1
            kind: Pod
            metadata:
              namespace: ${local.namespace}
            spec:
              containers:
                - name: postgres
                  image: postgres:16-alpine
                  command:
                    - cat
                  tty: true
                  env:
                    - name: PGHOST
                      value: ${local.rw_host}
                    - name: PGPORT
                      value: "5432"
                    - name: PGUSER
                      valueFrom:
                        secretKeyRef:
                          name: ${local.app_secret_name}
                          key: username
                    - name: PGPASSWORD
                      valueFrom:
                        secretKeyRef:
                          name: ${local.app_secret_name}
                          key: password
                - name: mc
                  image: quay.io/minio/mc:latest
                  command:
                    - cat
                  tty: true
                  env:
                    - name: S3_ENDPOINT
                      value: ${var.s3_endpoint_url}
                    - name: S3_ACCESS_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.s3_credentials_secret}
                          key: ACCESS_KEY_ID
                    - name: S3_SECRET_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.s3_credentials_secret}
                          key: ACCESS_SECRET_KEY
                    - name: DUMP_BUCKET
                      value: ${local.dump_bucket}
            """) {
              node(POD_LABEL) {
                stage('Dump') {
                  container('postgres') {
                    sh 'set -eu; SAFE_LABEL=$(printf "%s" "$DUMP_LABEL" | tr -c "A-Za-z0-9._-" "-"); DATE=$(date -u +%Y%m%dT%H%M%SZ); DUMP_FILE="$DATABASE-$SAFE_LABEL-$DATE.dump"; pg_dump -Fc -d "$DATABASE" -f "$DUMP_FILE"; printf "%s" "$DUMP_FILE" > dump-name.txt; ls -lh "$DUMP_FILE"'
                  }
                }

                stage('Upload') {
                  container('mc') {
                    sh 'set -eu; DUMP_FILE=$(cat dump-name.txt); mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc mb --ignore-existing "target/$DUMP_BUCKET"; mc cp "$DUMP_FILE" "target/$DUMP_BUCKET/${local.dump_path}/$DUMP_FILE"; echo "Uploaded: s3://$DUMP_BUCKET/${local.dump_path}/$DUMP_FILE"'
                  }
                }
              }
            }
          ''')
        }
      }
    }
  EOT

  restore_job_script = <<-EOT
    pipelineJob('aof-db-restore-dev') {
      description('Restores a logical dump into the dedicated dev restore database. This job intentionally does not target production.')
      keepDependencies(false)
      parameters {
        stringParam('DUMP_OBJECT', '', 'Object key inside ${local.dump_bucket}, for example ${local.dump_path}/aof-manual-20260525T120000Z.dump.')
        stringParam('TARGET_DATABASE', 'aof_dev_restore', 'Existing dev database to restore into.')
        booleanParam('RESET_SCHEMA', true, 'Drop and recreate public schema before restoring.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            podTemplate(namespace: '${local.namespace}', yaml: """
            apiVersion: v1
            kind: Pod
            metadata:
              namespace: ${local.namespace}
            spec:
              containers:
                - name: postgres
                  image: postgres:16-alpine
                  command:
                    - cat
                  tty: true
                  env:
                    - name: PGHOST
                      value: ${local.rw_host}
                    - name: PGPORT
                      value: "5432"
                    - name: PGUSER
                      valueFrom:
                        secretKeyRef:
                          name: ${local.app_secret_name}
                          key: username
                    - name: PGPASSWORD
                      valueFrom:
                        secretKeyRef:
                          name: ${local.app_secret_name}
                          key: password
                - name: mc
                  image: quay.io/minio/mc:latest
                  command:
                    - cat
                  tty: true
                  env:
                    - name: S3_ENDPOINT
                      value: ${var.s3_endpoint_url}
                    - name: S3_ACCESS_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.s3_credentials_secret}
                          key: ACCESS_KEY_ID
                    - name: S3_SECRET_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.s3_credentials_secret}
                          key: ACCESS_SECRET_KEY
                    - name: DUMP_BUCKET
                      value: ${local.dump_bucket}
            """) {
              node(POD_LABEL) {
                stage('Download') {
                  container('mc') {
                    sh 'set -eu; test -n "$DUMP_OBJECT"; mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc cp "target/$DUMP_BUCKET/$DUMP_OBJECT" restore.dump; ls -lh restore.dump'
                  }
                }

                stage('Restore') {
                  container('postgres') {
                    sh 'set -eu; if [ "$RESET_SCHEMA" = "true" ]; then psql -d "$TARGET_DATABASE" -v ON_ERROR_STOP=1 -v owner="$PGUSER" -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public AUTHORIZATION \\"$PGUSER\\";"; fi; pg_restore --no-owner --no-acl --clean --if-exists -d "$TARGET_DATABASE" restore.dump'
                  }
                }
              }
            }
          ''')
        }
      }
    }
  EOT
}

resource "kubernetes_namespace" "database" {
  metadata {
    name = local.namespace
  }
}

resource "kubernetes_secret" "app" {
  metadata {
    name      = local.app_secret_name
    namespace = kubernetes_namespace.database.metadata[0].name
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = local.app_user
    password = var.app_password
  }
}

resource "kubernetes_secret" "s3" {
  metadata {
    name      = local.s3_credentials_secret
    namespace = kubernetes_namespace.database.metadata[0].name
  }

  data = {
    ACCESS_KEY_ID     = var.s3_access_key
    ACCESS_SECRET_KEY = var.s3_secret_key
  }
}

resource "kubernetes_role_binding" "jenkins_database_jobs" {
  count = var.enable_jenkins_database_jobs ? 1 : 0

  metadata {
    name      = "jenkins-database-jobs"
    namespace = kubernetes_namespace.database.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = var.jenkins_namespace
  }
}

resource "kubernetes_job_v1" "object_store_bootstrap" {
  metadata {
    name      = "aof-postgres-object-store-bootstrap"
    namespace = kubernetes_namespace.database.metadata[0].name
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
              set -eu
              mc alias set target '${var.s3_endpoint_url}' '${var.s3_access_key}' '${var.s3_secret_key}'
              mc mb --ignore-existing 'target/${local.backup_bucket}'
              mc mb --ignore-existing 'target/${local.dump_bucket}'
            EOT
          ]
        }
      }
    }
  }

  wait_for_completion = true
}

resource "helm_release" "cluster" {
  name       = local.cluster_name
  namespace  = kubernetes_namespace.database.metadata[0].name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cluster"
  version    = "0.6.1"
  timeout    = 1200

  values = [
    yamlencode({
      fullnameOverride  = local.cluster_name
      namespaceOverride = local.namespace
      type              = "postgresql"

      version = {
        postgresql = "16"
      }

      mode       = "standalone"
      database   = local.app_database
      owner      = local.app_user
      secretName = kubernetes_secret.app.metadata[0].name

      cluster = {
        instances = var.cluster_instances

        storage = {
          size         = var.storage_size
          storageClass = var.storage_class
        }

        walStorage = {
          enabled      = true
          size         = var.wal_storage_size
          storageClass = var.wal_storage_class
        }

        resources = var.postgres_resources

        enableSuperuserAccess = false
        enablePDB             = var.enable_pdb
        affinity              = var.postgres_affinity

        initdb = {
          database = local.app_database
          owner    = local.app_user
          secret = {
            name = kubernetes_secret.app.metadata[0].name
          }
        }

        postgresql = {
          parameters = var.postgres_parameters
        }
      }

      backups = {
        enabled         = true
        provider        = "s3"
        endpointURL     = var.s3_endpoint_url
        destinationPath = "s3://${local.backup_bucket}/${local.backup_path}"
        retentionPolicy = var.backup_retention_policy

        s3 = {
          region    = var.s3_region
          bucket    = local.backup_bucket
          path      = local.backup_path
          accessKey = var.s3_access_key
          secretKey = var.s3_secret_key
        }

        secret = {
          create = false
          name   = local.s3_credentials_secret
        }

        wal = {
          compression = "gzip"
          encryption  = ""
          maxParallel = 2
        }

        data = {
          compression = "gzip"
          encryption  = ""
          jobs        = 2
        }

        scheduledBackups = [
          {
            name                 = "daily-backup"
            schedule             = var.backup_schedule
            backupOwnerReference = "self"
            method               = "barmanObjectStore"
            retentionPolicy      = var.backup_retention_policy
          }
        ]
      }

      databases = [
        {
          name  = "aof_dev_restore"
          owner = local.app_user
        }
      ]

      poolers = [
        {
          name       = "rw"
          type       = "rw"
          poolMode   = "transaction"
          instances  = var.pooler_instances
          parameters = var.pooler_parameters
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_job_v1.object_store_bootstrap
  ]
}
