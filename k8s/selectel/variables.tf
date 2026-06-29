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

variable "aof_back_image_tag" {
  description = "Container image tag for the initial aof-back Helm releases."
  type        = string
  default     = "latest"
}

variable "aof_back_image_pull_secret_names" {
  description = "Optional imagePullSecrets used by aof-back pods."
  type        = list(string)
  default     = []
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
