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

variable "selectel_auth_region" {
  description = "Selectel authentication region."
  type        = string
  default     = "pool"
}

variable "selectel_auth_url" {
  description = "Selectel Keystone Identity authentication URL."
  type        = string
  default     = "https://cloud.api.selcloud.ru/identity/v3/"
}
