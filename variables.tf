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
  description = "Selectel project ID where Container Registry will be created."
  type        = string
  nullable    = false
}

variable "registry_name" {
  description = "Selectel Container Registry name. Use lowercase letters, digits, and hyphens; max 20 characters."
  type        = string
  default     = "aof-registry"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.registry_name))
    error_message = "registry_name must start with a lowercase letter, end with a lowercase letter or digit, contain only lowercase letters, digits, and hyphens, and be 2-20 characters long."
  }
}

variable "jenkins_admin_password" {
  description = "Initial Jenkins admin password when Jenkins is enabled."
  type        = string
  sensitive   = true
  default     = null
}
