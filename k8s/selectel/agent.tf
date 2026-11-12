module "aof_agent" {
  source       = "../../modules/agent"
  image_digest = var.agent_image_digest
}

variable "agent_image_digest" {
  type        = string
  default     = null
  description = "New agent runtime digest; null preserves its currently running image."
}

output "agent_runtime_image_digest" {
  value = module.aof_agent.runtime_image_digest
}
