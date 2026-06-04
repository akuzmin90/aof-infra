variable "app_password" {
  description = "Password for the aof database owner."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Short instance name, for example feature or release."
  type        = string
}

variable "namespace" {
  description = "Namespace where this PostgreSQL instance is deployed."
  type        = string
}

variable "create_namespace" {
  description = "Create the namespace before installing PostgreSQL."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "CloudNativePG cluster name."
  type        = string
}

variable "app_database" {
  description = "Application database name."
  type        = string
  default     = "aof"
}

variable "app_user" {
  description = "Application database user."
  type        = string
  default     = "aof"
}

variable "app_secret_name" {
  description = "Kubernetes secret name for application database credentials."
  type        = string
  default     = ""
}

variable "backup_bucket" {
  description = "S3 bucket for physical backups and WAL archive."
  type        = string
  default     = "aof-postgres-backups"
}

variable "dump_bucket" {
  description = "S3 bucket for manual logical dumps."
  type        = string
  default     = "aof-postgres-dumps"
}

variable "s3_endpoint_url" {
  description = "S3-compatible endpoint used for PostgreSQL physical backups and logical dumps."
  type        = string
}

variable "s3_region" {
  description = "S3 region."
  type        = string
  default     = "us-east-1"
}

variable "s3_access_key" {
  description = "S3 access key."
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "S3 secret key."
  type        = string
  sensitive   = true
}

variable "jenkins_namespace" {
  description = "Namespace where Jenkins agent pods run."
  type        = string
  default     = "jenkins"
}

variable "enable_jenkins_database_jobs" {
  description = "Create RBAC and expose Jenkins Job DSL scripts for database dump/restore jobs."
  type        = bool
  default     = false
}

variable "cluster_instances" {
  description = "Number of PostgreSQL instances."
  type        = number
  default     = 2
}

variable "storage_size" {
  description = "PostgreSQL data volume size."
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "StorageClass for PostgreSQL data volumes. Empty uses the cluster default."
  type        = string
  default     = ""
}

variable "wal_storage_size" {
  description = "PostgreSQL WAL volume size."
  type        = string
  default     = "2Gi"
}

variable "wal_storage_class" {
  description = "StorageClass for PostgreSQL WAL volumes. Empty uses the cluster default."
  type        = string
  default     = ""
}

variable "postgres_resources" {
  description = "CPU and memory requests/limits for PostgreSQL pods."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "2"
      memory = "2Gi"
    }
  }
}

variable "postgres_parameters" {
  description = "postgresql.conf parameters tuned per environment."
  type        = map(string)
  default = {
    max_connections                     = "250"
    shared_buffers                      = "512MB"
    effective_cache_size                = "1536MB"
    maintenance_work_mem                = "128MB"
    checkpoint_completion_target        = "0.9"
    wal_compression                     = "on"
    random_page_cost                    = "1.1"
    effective_io_concurrency            = "200"
    idle_in_transaction_session_timeout = "60000"
  }
}

variable "postgres_affinity" {
  description = "CloudNativePG Cluster spec affinity, including nodeSelector and tolerations."
  type        = any
  default     = {}
}

variable "enable_pdb" {
  description = "Enable CloudNativePG generated PodDisruptionBudget."
  type        = bool
  default     = false
}

variable "backup_retention_policy" {
  description = "Physical backup retention policy."
  type        = string
  default     = "14d"
}

variable "backup_schedule" {
  description = "CloudNativePG scheduled backup cron expression."
  type        = string
  default     = "0 0 2 * * *"
}

variable "pooler_instances" {
  description = "Number of PgBouncer read-write pooler instances."
  type        = number
  default     = 2
}

variable "pooler_parameters" {
  description = "PgBouncer pooler parameters."
  type        = map(string)
  default = {
    max_client_conn   = "1000"
    default_pool_size = "25"
  }
}
