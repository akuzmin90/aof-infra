variable "namespace" {
  description = "Namespace for Grafana, Loki, and Alloy."
  type        = string
  default     = "observability"
}

variable "s3_endpoint_url" {
  description = "S3-compatible endpoint for Loki object storage."
  type        = string
}

variable "s3_region" {
  description = "S3 region for Loki object storage."
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket used by Loki."
  type        = string
}

variable "s3_access_key" {
  description = "S3 access key used by Loki."
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "S3 secret key used by Loki."
  type        = string
  sensitive   = true
}

variable "log_namespaces" {
  description = "Kubernetes namespaces whose pod logs Alloy should send to Loki."
  type        = list(string)
  default = [
    "observability",
    "aof-dev",
    "aof-feature",
    "aof-release",
    "public-sites",
    "ingress-nginx",
    "cert-manager",
    "jenkins",
    "cnpg-system",
  ]
}

variable "grafana_public_url" {
  description = "Optional external URL where Grafana is served."
  type        = string
  default     = null
}

variable "grafana_public_sub_path" {
  description = "Optional external sub-path where Grafana is served."
  type        = string
  default     = null
}
