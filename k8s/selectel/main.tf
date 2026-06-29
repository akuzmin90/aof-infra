terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    endpoints = {
      s3 = "https://s3.ru-7.storage.selcloud.ru"
    }
    key                         = "aof-k8s.tfstate"
    region                      = "ru-7"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
    use_path_style              = true
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "openstack" {
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3"
  domain_name = var.selectel_domain_name
  tenant_id   = var.selectel_project_id
  user_name   = var.selectel_username
  password    = var.selectel_password
  region      = "ru-7"
}

import {
  to = module.frontend_gateway["feature"].kubernetes_secret.s3
  id = "aof-feature/frontend-gateway-s3"
}

import {
  to = module.frontend_gateway["feature"].kubernetes_config_map.proxy
  id = "aof-feature/frontend-gateway-proxy"
}

removed {
  from = helm_release.aof_back

  lifecycle {
    destroy = false
  }
}

removed {
  from = random_password.aof_back_client_id

  lifecycle {
    destroy = false
  }
}

moved {
  from = kubernetes_ingress_v1.grafana_temporary
  to   = kubernetes_ingress_v1.grafana
}

module "ingress_nginx" {
  source = "../../modules/ingress-nginx"
}

module "cert_manager" {
  source = "../../modules/cert-manager"
}

module "cloudnative_pg_operator" {
  source = "../../modules/cloudnative-pg-operator"
}

resource "random_password" "jenkins_admin" {
  length  = 24
  special = false
}

locals {
  app_instances = {
    dev = {
      namespace        = "aof-dev"
      database_cluster = "aof-dev-db"
    }
    feature = {
      namespace        = "aof-feature"
      database_cluster = "aof-feature-db"
    }
    release = {
      namespace        = "aof-release"
      database_cluster = "aof-release-db"
    }
  }

  public_sites_namespace = "public-sites"
  public_sites_backup_s3 = {
    endpoint_url = "https://s3.ru-7.storage.selcloud.ru"
    region       = "ru-7"
    bucket       = "hitmakers-public-sites-backups"
    secret_name  = "public-sites-backup-s3"
  }

  observability_namespace = "observability"

  public_sites = {
    l-zazer = {
      hosts                    = ["l.zazer.mobi"]
      files_size               = "10Gi"
      db_size                  = "10Gi"
      backup_s3_site_prefix    = "l-zazer-mobi"
      restore_strip_components = 0
      restore_s3_backup_path   = "l-zazer-mobi/20260617-091610"
    }
    hitmakers = {
      hosts                    = ["hitmakers.games", "hitmakers.website"]
      files_size               = "20Gi"
      db_size                  = "10Gi"
      backup_s3_site_prefix    = "hitmakers-copy"
      restore_strip_components = 1
      restore_s3_backup_path   = "hitmakers-copy/20260617-091610"
    }
  }

  database_node_affinity = {
    nodeSelector = {
      workload = "database"
    }
    tolerations = [
      {
        key      = "dedicated"
        operator = "Equal"
        value    = "database"
        effect   = "NoSchedule"
      }
    ]
  }

  small_postgres_resources = {
    requests = {
      cpu    = "250m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }

  small_postgres_parameters = {
    max_connections                     = "150"
    shared_buffers                      = "512MB"
    effective_cache_size                = "1536MB"
    maintenance_work_mem                = "128MB"
    work_mem                            = "4MB"
    checkpoint_completion_target        = "0.9"
    max_wal_size                        = "2GB"
    min_wal_size                        = "512MB"
    wal_compression                     = "on"
    random_page_cost                    = "1.1"
    effective_io_concurrency            = "200"
    idle_in_transaction_session_timeout = "60000"
  }
}

resource "random_password" "postgres_app" {
  for_each = local.app_instances

  length  = 32
  special = false
}

resource "random_password" "wordpress_db" {
  for_each = var.public_sites_enabled ? local.public_sites : {}

  length  = 32
  special = false
}

resource "random_password" "wordpress_db_root" {
  for_each = var.public_sites_enabled ? local.public_sites : {}

  length  = 32
  special = false
}

resource "random_password" "dedicated_logs_basic_auth" {
  length  = 32
  special = false
}

resource "kubernetes_namespace" "app" {
  for_each = local.app_instances

  metadata {
    name = each.value.namespace
  }
}

resource "kubernetes_namespace" "public_sites" {
  count = var.public_sites_enabled ? 1 : 0

  metadata {
    name = local.public_sites_namespace
  }
}

resource "openstack_objectstorage_container_v1" "public_sites_backups" {
  name          = local.public_sites_backup_s3.bucket
  region        = local.public_sites_backup_s3.region
  force_destroy = false
}

resource "kubernetes_secret" "public_sites_backup_s3" {
  count = var.public_sites_enabled ? 1 : 0

  metadata {
    name      = local.public_sites_backup_s3.secret_name
    namespace = local.public_sites_namespace

    labels = {
      "app.kubernetes.io/name"       = "public-sites"
      "app.kubernetes.io/component"  = "backup-s3"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    endpoint-url          = local.public_sites_backup_s3.endpoint_url
    region                = local.public_sites_backup_s3.region
    bucket                = openstack_objectstorage_container_v1.public_sites_backups.name
    access-key            = var.public_sites_backup_s3_access_key
    secret-key            = var.public_sites_backup_s3_secret_key
    AWS_ENDPOINT_URL      = local.public_sites_backup_s3.endpoint_url
    AWS_DEFAULT_REGION    = local.public_sites_backup_s3.region
    AWS_ACCESS_KEY_ID     = var.public_sites_backup_s3_access_key
    AWS_SECRET_ACCESS_KEY = var.public_sites_backup_s3_secret_key
  }

  depends_on = [
    kubernetes_namespace.public_sites
  ]
}

resource "kubernetes_secret" "registry_pull" {
  for_each = local.app_instances

  metadata {
    name      = "selectel-registry"
    namespace = each.value.namespace
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

  depends_on = [
    kubernetes_namespace.app
  ]
}

module "redis" {
  for_each = local.app_instances

  source = "../../modules/redis"

  namespace        = each.value.namespace
  create_namespace = false

  depends_on = [
    kubernetes_namespace.app
  ]
}

module "ignite" {
  for_each = local.app_instances

  source = "../../modules/ignite"

  namespace        = each.value.namespace
  create_namespace = false

  depends_on = [
    kubernetes_namespace.app
  ]
}

module "rabbitmq" {
  for_each = local.app_instances

  source = "../../modules/rabbitmq"

  namespace        = each.value.namespace
  create_namespace = false

  depends_on = [
    kubernetes_namespace.app
  ]
}

module "postgresql_cluster" {
  for_each = local.app_instances

  source = "../../modules/postgresql-cluster"

  name             = each.key
  namespace        = each.value.namespace
  cluster_name     = each.value.database_cluster
  create_namespace = false

  app_password    = random_password.postgres_app[each.key].result
  s3_endpoint_url = var.postgres_s3_endpoint_url
  s3_region       = var.postgres_s3_region
  s3_access_key   = var.postgres_s3_access_key
  s3_secret_key   = var.postgres_s3_secret_key

  enable_jenkins_database_jobs = false

  cluster_instances = 1
  storage_size      = "20Gi"
  storage_class     = "fast.ru-7a"
  wal_storage_size  = "32Gi"
  wal_storage_class = "fast.ru-7a"

  postgres_resources  = local.small_postgres_resources
  postgres_affinity   = local.database_node_affinity
  postgres_parameters = local.small_postgres_parameters

  pooler_instances = 1
  pooler_parameters = {
    max_client_conn   = "500"
    default_pool_size = "20"
    reserve_pool_size = "5"
  }

  backup_retention_policy = "7d"
  backup_schedule         = "0 0 2 * * *"

  depends_on = [
    module.cloudnative_pg_operator,
    kubernetes_namespace.app
  ]
}

module "frontend_gateway" {
  for_each = local.app_instances

  source = "../../modules/frontend-gateway"

  name             = "frontend-gateway"
  namespace        = each.value.namespace
  create_namespace = false
  host             = "${each.key}.${var.app_domain_suffix}"
  s3_origin        = var.frontend_s3_endpoint_url
  s3_host_header   = replace(var.frontend_s3_endpoint_url, "https://", "")
  s3_region        = var.postgres_s3_region
  s3_access_key    = var.frontend_s3_access_key
  s3_secret_key    = var.frontend_s3_secret_key
  bucket           = var.frontend_s3_buckets[each.key]
  prefix           = ""

  depends_on = [
    kubernetes_namespace.app
  ]
}

module "public_sites" {
  for_each = var.public_sites_enabled ? local.public_sites : {}

  source = "../../modules/public-sites"

  name      = each.key
  namespace = local.public_sites_namespace
  hosts     = each.value.hosts

  db_password      = random_password.wordpress_db[each.key].result
  db_root_password = random_password.wordpress_db_root[each.key].result

  files_size = each.value.files_size
  db_size    = each.value.db_size

  backup_s3_site_prefix = each.value.backup_s3_site_prefix

  restore_generation       = 0
  restore_backup_pvc_name  = null
  restore_backup_path      = null
  restore_strip_components = each.value.restore_strip_components
  restore_s3_backup_path   = each.value.restore_s3_backup_path

  tls_enabled         = var.public_sites_tls_enabled
  cluster_issuer_name = module.cert_manager.cluster_issuer_name

  depends_on = [
    kubernetes_namespace.public_sites,
    module.ingress_nginx
  ]
}

module "observability" {
  source = "../../modules/observability"

  namespace       = local.observability_namespace
  s3_endpoint_url = var.observability_loki_s3_endpoint_url
  s3_region       = var.observability_loki_s3_region
  s3_bucket       = var.observability_loki_s3_bucket
  s3_access_key   = coalesce(var.observability_s3_access_key, var.postgres_s3_access_key)
  s3_secret_key   = coalesce(var.observability_s3_secret_key, var.postgres_s3_secret_key)

  grafana_public_url      = "https://grafana.${var.app_domain_suffix}"
  grafana_public_sub_path = null
}

resource "kubernetes_secret" "dedicated_logs_basic_auth" {
  metadata {
    name      = "dedicated-logs-basic-auth"
    namespace = module.observability.namespace

    labels = {
      "app.kubernetes.io/name"       = "alloy-gateway"
      "app.kubernetes.io/component"  = "dedicated-logs-auth"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    auth = "alloy:${random_password.dedicated_logs_basic_auth.bcrypt_hash}"
  }

  depends_on = [
    module.observability
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = module.observability.namespace

    annotations = {
      "cert-manager.io/cluster-issuer"              = module.cert_manager.cluster_issuer_name
      "nginx.ingress.kubernetes.io/proxy-body-size" = "16m"
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "grafana.${var.app_domain_suffix}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = module.observability.grafana_service_name

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["grafana.${var.app_domain_suffix}"]
      secret_name = "grafana-k8s-zazer-fun-tls"
    }
  }

  depends_on = [
    module.ingress_nginx,
    module.cert_manager,
    module.observability
  ]
}

resource "kubernetes_ingress_v1" "dedicated_logs_gateway" {
  metadata {
    name      = "dedicated-logs-gateway"
    namespace = module.observability.namespace

    annotations = {
      "cert-manager.io/cluster-issuer"              = module.cert_manager.cluster_issuer_name
      "nginx.ingress.kubernetes.io/auth-realm"      = "dedicated logs"
      "nginx.ingress.kubernetes.io/auth-secret"     = kubernetes_secret.dedicated_logs_basic_auth.metadata[0].name
      "nginx.ingress.kubernetes.io/auth-type"       = "basic"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "16m"
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "grafana.${var.app_domain_suffix}"

      http {
        path {
          path      = "/loki/api/v1/push"
          path_type = "Exact"

          backend {
            service {
              name = module.observability.alloy_gateway_service_name

              port {
                name = "loki-push"
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["grafana.${var.app_domain_suffix}"]
      secret_name = "grafana-k8s-zazer-fun-tls"
    }
  }

  depends_on = [
    module.ingress_nginx,
    module.cert_manager,
    module.observability
  ]
}

resource "kubernetes_ingress_v1" "frontend" {
  for_each = local.app_instances

  metadata {
    name      = "frontend"
    namespace = each.value.namespace

    annotations = {
      "cert-manager.io/cluster-issuer"              = module.cert_manager.cluster_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "64m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "${each.key}.${var.app_domain_suffix}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = module.frontend_gateway[each.key].service_name

              port {
                number = 8080
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["${each.key}.${var.app_domain_suffix}"]
      secret_name = "${each.key}-k8s-zazer-fun-tls"
    }
  }
}

module "jenkins" {
  source = "../../modules/jenkins"

  admin_password            = random_password.jenkins_admin.result
  persistence_storage_class = "fast.ru-7a"
  public_url                = "https://${var.jenkins_host}/"

  frontend_job_name        = "aof-front"
  frontend_job_description = "Builds aof-front and uploads dist/ to S3."
  frontend_s3_endpoint_url = var.frontend_s3_endpoint_url
  frontend_s3_buckets      = var.frontend_s3_buckets
  frontend_s3_access_key   = var.frontend_s3_access_key
  frontend_s3_secret_key   = var.frontend_s3_secret_key
  frontend_instances       = keys(local.app_instances)
  postgres_s3_endpoint_url = var.postgres_s3_endpoint_url

  backend_job_name         = "aof-back"
  backend_image_repository = var.aof_back_image_repository
  app_domain_suffix        = var.app_domain_suffix
  registry_server          = var.registry_server
  registry_username        = var.registry_username
  registry_password        = var.registry_password
}

resource "kubernetes_ingress_v1" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = module.jenkins.namespace

    annotations = {
      "cert-manager.io/cluster-issuer"                 = module.cert_manager.cluster_issuer_name
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "64m"
      "nginx.ingress.kubernetes.io/proxy-buffering"    = "off"
      "nginx.ingress.kubernetes.io/proxy-http-version" = "1.1"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/upstream-vhost"     = var.jenkins_host
      "nginx.ingress.kubernetes.io/x-forwarded-prefix" = "/"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.jenkins_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "jenkins"

              port {
                number = 8080
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [var.jenkins_host]
      secret_name = "jenkins-k8s-zazer-fun-tls"
    }
  }
}
