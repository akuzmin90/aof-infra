variable "kubeconfig_path" {
  description = "Path to the Selectel MKS kubeconfig."
  type        = string
  default     = "../../cloud/selectel/kubeconfig.yaml"
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
