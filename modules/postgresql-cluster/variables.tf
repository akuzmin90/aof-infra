variable "app_password" {
  description = "Password for the aof database owner."
  type        = string
  sensitive   = true
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
