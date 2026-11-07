variable "kubeconfig_path" {
  description = "Path to the Selectel MKS kubeconfig."
  type        = string
  default     = "../../cloud/selectel/kubeconfig.yaml"
}

variable "selectel_domain_name" {
  description = "Selectel account ID."
  type        = string
}

variable "selectel_username" {
  description = "Selectel service user name."
  type        = string
}

variable "selectel_password" {
  description = "Selectel service user password."
  type        = string
  sensitive   = true
}

variable "selectel_project_id" {
  description = "Selectel project ID where object storage credentials are created."
  type        = string
}

variable "postgres_s3_endpoint_url" {
  description = "Selectel S3-compatible endpoint for PostgreSQL backups and dumps."
  type        = string
  default     = "https://s3.ru-7.storage.selcloud.ru"
}

variable "postgres_s3_region" {
  description = "S3 region for PostgreSQL backups and dumps."
  type        = string
  default     = "ru-7"
}

variable "postgres_s3_access_key" {
  description = "S3 access key for PostgreSQL backups and dumps."
  type        = string
  sensitive   = true
}

variable "postgres_s3_secret_key" {
  description = "S3 secret key for PostgreSQL backups and dumps."
  type        = string
  sensitive   = true
}

variable "frontend_s3_endpoint_url" {
  description = "Selectel S3-compatible endpoint used by Jenkins to upload frontend assets."
  type        = string
  default     = "https://s3.ru-7.storage.selcloud.ru"
}

variable "frontend_s3_buckets" {
  description = "Per-instance Selectel S3 buckets used by Jenkins and frontend gateways."
  type        = map(string)
  default = {
    dev     = "hitmakers-aof-front-dev"
    feature = "hitmakers-aof-front-feature"
    release = "hitmakers-aof-front-release"
  }
}

variable "frontend_s3_bucket" {
  description = "Deprecated compatibility variable. Use frontend_s3_buckets."
  type        = string
  default     = null
}

variable "frontend_s3_access_key" {
  description = "S3 access key used by Jenkins to upload frontend assets."
  type        = string
  sensitive   = true
}

variable "frontend_s3_secret_key" {
  description = "S3 secret key used by Jenkins to upload frontend assets."
  type        = string
  sensitive   = true
}

variable "app_domain_suffix" {
  description = "Base domain used for per-instance aof-back ingress hosts."
  type        = string
  default     = "k8s.zazer.fun"
}

variable "legacy_app_domain_suffix" {
  description = "Legacy Kayra domain added to application ingresses for DNS cutover."
  type        = string
  default     = "zazer.fun"
}

variable "legacy_runtime_services_enabled" {
  description = "Keep Redis, Ignite, RabbitMQ, and PgBouncer during the staged migration from the old Kubernetes backend image."
  type        = bool
  default     = false
}

variable "dev_db_storage_migration_stage" {
  description = "Dev PostgreSQL Fast-to-Universal migration stage: disabled, copy, replicate, cutover, or complete."
  type        = string
  default     = "complete"

  validation {
    condition = contains([
      "disabled",
      "copy",
      "replicate",
      "cutover",
      "complete",
    ], var.dev_db_storage_migration_stage)
    error_message = "dev_db_storage_migration_stage must be disabled, copy, replicate, cutover, or complete."
  }
}

variable "feature_db_storage_migration_stage" {
  description = "Feature PostgreSQL Fast-to-Universal migration stage: disabled, copy, replicate, cutover, or complete."
  type        = string
  default     = "complete"

  validation {
    condition = contains([
      "disabled",
      "copy",
      "replicate",
      "cutover",
      "complete",
    ], var.feature_db_storage_migration_stage)
    error_message = "feature_db_storage_migration_stage must be disabled, copy, replicate, cutover, or complete."
  }
}

variable "release_db_storage_migration_stage" {
  description = "Release PostgreSQL Fast-to-Universal migration stage: disabled, copy, replicate, cutover, or complete."
  type        = string
  default     = "complete"

  validation {
    condition = contains([
      "disabled",
      "copy",
      "replicate",
      "cutover",
      "complete",
    ], var.release_db_storage_migration_stage)
    error_message = "release_db_storage_migration_stage must be disabled, copy, replicate, cutover, or complete."
  }
}

variable "jenkins_host" {
  description = "Jenkins ingress host."
  type        = string
  default     = "jenkins.k8s.zazer.fun"
}

variable "aof_back_image_repository" {
  description = "Container image repository for aof-back."
  type        = string
  default     = "cr.selcloud.ru/aof-registry/aof-back"
}

variable "content_manager_host" {
  description = "Public host of aof-content-manager."
  type        = string
  default     = "content.zazer.fun"
}

variable "content_manager_image_repository" {
  description = "Container image repository for aof-content-manager."
  type        = string
  default     = "cr.selcloud.ru/aof-registry/aof-content-manager"
}

variable "content_manager_admins" {
  description = "Initial CM_ADMINS for aof-content-manager (login:bcrypt-hash, comma-separated), used only when the Secret is created; afterwards the list is maintained in the cluster. Hash: htpasswd -nbBC 10 \"\" 'password' | tr -d ':\\n'"
  type        = string
  sensitive   = true
  default     = ""
}

variable "content_manager_git_username" {
  description = "CM_GIT_USERNAME: GitHub login of the read-only technical account. Empty means x-access-token."
  type        = string
  default     = ""
}

variable "content_manager_git_token" {
  description = "CM_GIT_TOKEN: classic PAT (scope repo) of the technical account with Read access to aof-back and aof-front. The service never pushes."
  type        = string
  sensitive   = true
}

variable "registry_server" {
  description = "Container registry server."
  type        = string
  default     = "cr.selcloud.ru"
}

variable "registry_username" {
  description = "Container registry username."
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "Container registry password/token."
  type        = string
  sensitive   = true
}

variable "public_sites_enabled" {
  description = "Deploy the public legacy website instances."
  type        = bool
  default     = false
}

variable "public_sites_tls_enabled" {
  description = "Enable cert-manager TLS for public site ingresses after DNS points to the cluster."
  type        = bool
  default     = false
}

variable "public_sites_backup_s3_access_key" {
  description = "S3 access key used for public sites backups."
  type        = string
  sensitive   = true
}

variable "public_sites_backup_s3_secret_key" {
  description = "S3 secret key used for public sites backups."
  type        = string
  sensitive   = true
}

variable "observability_s3_access_key" {
  description = "Optional S3 access key used by Loki for observability logs. Defaults to postgres_s3_access_key when null."
  type        = string
  default     = null
  sensitive   = true
}

variable "observability_s3_secret_key" {
  description = "Optional S3 secret key used by Loki for observability logs. Defaults to postgres_s3_secret_key when null."
  type        = string
  default     = null
  sensitive   = true
}

variable "observability_loki_s3_endpoint_url" {
  description = "Selectel S3-compatible endpoint used by Loki."
  type        = string
  default     = "https://s3.ru-7.storage.selcloud.ru"
}

variable "observability_loki_s3_region" {
  description = "S3 region used by Loki."
  type        = string
  default     = "ru-7"
}

variable "observability_loki_s3_bucket" {
  description = "S3 bucket used by Loki for durable log storage. The bucket is owned by cloud/selectel."
  type        = string
  default     = "hitmakers-loki-logs"
}
