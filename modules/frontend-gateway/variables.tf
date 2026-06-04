variable "namespace" {
  description = "Namespace where the frontend gateway is deployed."
  type        = string
  default     = "frontend"
}

variable "create_namespace" {
  description = "Create the namespace before installing the frontend gateway."
  type        = bool
  default     = true
}

variable "name" {
  description = "Frontend gateway resource name."
  type        = string
  default     = "frontend-gateway"
}

variable "host" {
  description = "Host served by this gateway."
  type        = string
  default     = "dev.hitmakers.ru"
}

variable "s3_origin" {
  description = "HTTP origin for S3-compatible object storage, without trailing slash."
  type        = string
  default     = "http://minio.minio.svc.cluster.local:9000"
}

variable "s3_host_header" {
  description = "Host header to send to the S3 origin."
  type        = string
  default     = "minio.minio.svc.cluster.local"
}

variable "s3_region" {
  description = "S3 region used for AWS Signature V4."
  type        = string
  default     = "us-east-1"
}

variable "s3_access_key" {
  description = "S3 access key used by the authenticated frontend gateway."
  type        = string
  sensitive   = true
  default     = "minioadmin"
}

variable "s3_secret_key" {
  description = "S3 secret key used by the authenticated frontend gateway."
  type        = string
  sensitive   = true
  default     = "minioadmin"
}

variable "bucket" {
  description = "S3 bucket name."
  type        = string
  default     = "aof-front"
}

variable "prefix" {
  description = "S3 key prefix for this frontend instance, without leading or trailing slash."
  type        = string
  default     = ""
}
