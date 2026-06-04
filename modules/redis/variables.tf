variable "namespace" {
  description = "Namespace where Redis is deployed."
  type        = string
}

variable "create_namespace" {
  description = "Create the namespace before installing Redis."
  type        = bool
  default     = true
}
