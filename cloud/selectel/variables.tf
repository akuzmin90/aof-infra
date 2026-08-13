variable "selectel_domain_name" {
  description = "Selectel account ID."
  type        = string
  nullable    = false
}

variable "selectel_username" {
  description = "Selectel service user name."
  type        = string
  nullable    = false
}

variable "selectel_password" {
  description = "Selectel service user password."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "selectel_project_id" {
  description = "Selectel project ID where cloud resources will be created."
  type        = string
  nullable    = false
}

variable "kubernetes_version" {
  description = "Explicit Managed Kubernetes version. Update deliberately rather than during unrelated infrastructure changes."
  type        = string
  default     = "1.35.3"
}

variable "frontend_s3_endpoint_url" {
  description = "Selectel S3 endpoint used to manage frontend bucket policies."
  type        = string
  default     = "https://s3.ru-7.storage.selcloud.ru"
}

variable "frontend_s3_access_key" {
  description = "S3 access key allowed to manage frontend bucket policies."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "frontend_s3_secret_key" {
  description = "S3 secret key allowed to manage frontend bucket policies."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "frontend_s3_publisher_user_id" {
  description = "Selectel user identifier allowed to publish frontend objects. This is the IAM user ID, not an S3 access key."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.frontend_s3_publisher_user_id)) > 0
    error_message = "Set frontend_s3_publisher_user_id to the Selectel IAM user ID that owns the Jenkins S3 key."
  }
}

variable "frontend_s3_policy_manager_user_id" {
  description = "Selectel service user identifier used by Terraform to manage and refresh the frontend buckets."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.frontend_s3_policy_manager_user_id)) > 0
    error_message = "Set frontend_s3_policy_manager_user_id to the Selectel IAM service user ID used by Terraform."
  }
}
