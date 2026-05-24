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
