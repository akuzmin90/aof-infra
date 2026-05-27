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
