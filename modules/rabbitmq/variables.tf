variable "namespace" {
  description = "Namespace where RabbitMQ is deployed."
  type        = string
}

variable "create_namespace" {
  description = "Create the namespace before installing RabbitMQ."
  type        = bool
  default     = true
}
