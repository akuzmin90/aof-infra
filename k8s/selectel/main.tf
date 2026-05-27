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

module "ingress_nginx" {
  source = "../../modules/ingress-nginx"
}

module "cert_manager" {
  source = "../../modules/cert-manager"
}

module "cloudnative_pg_operator" {
  source = "../../modules/cloudnative-pg-operator"
}

resource "random_password" "postgres_app" {
  length  = 32
  special = false
}

module "postgresql_cluster" {
  source = "../../modules/postgresql-cluster"

  app_password    = random_password.postgres_app.result
  s3_endpoint_url = var.postgres_s3_endpoint_url
  s3_region       = var.postgres_s3_region
  s3_access_key   = var.postgres_s3_access_key
  s3_secret_key   = var.postgres_s3_secret_key

  cluster_instances = 1
  storage_size      = "200Gi"
  storage_class     = "fast.ru-7a"
  wal_storage_size  = "50Gi"
  wal_storage_class = "fast.ru-7a"

  postgres_resources = {
    requests = {
      cpu    = "6"
      memory = "24Gi"
    }
    limits = {
      cpu    = "7"
      memory = "28Gi"
    }
  }

  postgres_affinity = {
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

  postgres_parameters = {
    max_connections                     = "500"
    shared_buffers                      = "8GB"
    effective_cache_size                = "22GB"
    maintenance_work_mem                = "1GB"
    work_mem                            = "16MB"
    checkpoint_completion_target        = "0.9"
    max_wal_size                        = "8GB"
    min_wal_size                        = "2GB"
    wal_compression                     = "on"
    random_page_cost                    = "1.1"
    effective_io_concurrency            = "200"
    idle_in_transaction_session_timeout = "60000"
  }

  pooler_instances = 2
  pooler_parameters = {
    max_client_conn   = "3000"
    default_pool_size = "80"
    reserve_pool_size = "20"
  }

  backup_retention_policy = "14d"
  backup_schedule         = "0 0 2 * * *"

  depends_on = [
    module.cloudnative_pg_operator
  ]
}
