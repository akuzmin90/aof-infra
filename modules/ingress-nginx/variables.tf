variable "values" {
  description = "Additional Helm values for environment-specific ingress-nginx behavior."
  type        = list(string)
  default     = []
}
