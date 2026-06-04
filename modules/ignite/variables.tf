variable "namespace" {
  description = "Namespace where Ignite is deployed."
  type        = string
}

variable "create_namespace" {
  description = "Create the namespace before installing Ignite."
  type        = bool
  default     = true
}
