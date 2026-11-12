variable "image_digest" {
  type        = string
  default     = null
  description = "New runtime digest. Omit to preserve the currently running image."
  validation {
    condition     = var.image_digest == null ? true : can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "Use an immutable sha256 image digest."
  }
}
