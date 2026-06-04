variable "admin_password" {
  description = "Initial Jenkins admin password."
  type        = string
  sensitive   = true
}

variable "extra_job_scripts" {
  description = "Additional Jenkins Job DSL scripts managed by other infrastructure modules."
  type        = list(string)
  default     = []
}

variable "persistence_storage_class" {
  description = "StorageClass for Jenkins home PVC. Empty uses the cluster default."
  type        = string
  default     = ""
}

variable "public_url" {
  description = "Public Jenkins URL used for Jenkins Location configuration."
  type        = string
  default     = ""
}

variable "frontend_job_name" {
  description = "Name of the Jenkins job that builds and uploads aof-front."
  type        = string
  default     = "aof-front-local-s3"
}

variable "frontend_job_description" {
  description = "Description of the Jenkins job that builds and uploads aof-front."
  type        = string
  default     = "Builds aof-front and uploads dist/ to the configured S3-compatible bucket."
}

variable "frontend_s3_endpoint_url" {
  description = "S3-compatible endpoint used by the frontend upload job."
  type        = string
  default     = "http://minio.minio.svc.cluster.local:9000"
}

variable "frontend_s3_buckets" {
  description = "Per-instance S3 buckets used by the frontend upload job."
  type        = map(string)
  default = {
    dev = "aof-front-dev"
  }
}

variable "frontend_s3_access_key" {
  description = "S3 access key used by the frontend upload job."
  type        = string
  sensitive   = true
  default     = "minioadmin"
}

variable "frontend_s3_secret_key" {
  description = "S3 secret key used by the frontend upload job."
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

variable "frontend_instances" {
  description = "Frontend deployment instances exposed as Jenkins choices."
  type        = list(string)
  default     = ["dev"]
}

variable "backend_job_name" {
  description = "Name of the Jenkins job that builds and deploys aof-back."
  type        = string
  default     = "aof-back-k8s"
}

variable "backend_image_repository" {
  description = "Full image repository used by the backend build job."
  type        = string
  default     = "cr.selcloud.ru/aof-registry/aof-back"
}

variable "postgres_s3_endpoint_url" {
  description = "S3-compatible endpoint used by database dump and restore jobs."
  type        = string
  default     = "https://s3.ru-7.storage.selcloud.ru"
}

variable "postgres_dump_bucket" {
  description = "S3 bucket used by manual PostgreSQL dump and restore jobs."
  type        = string
  default     = "aof-postgres-dumps"
}

variable "app_domain_suffix" {
  description = "Base domain used for per-instance ingress hosts."
  type        = string
  default     = "k8s.zazer.fun"
}

variable "registry_server" {
  description = "Container registry server used by the backend build job."
  type        = string
  default     = "cr.selcloud.ru"
}

variable "registry_username" {
  description = "Container registry username used by the backend build job."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_password" {
  description = "Container registry password/token used by the backend build job."
  type        = string
  sensitive   = true
  default     = ""
}
