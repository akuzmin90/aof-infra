variable "name" {
  description = "Stable Kubernetes object prefix for this legacy WordPress instance."
  type        = string
}

variable "namespace" {
  description = "Namespace where the WordPress instance is deployed."
  type        = string
}

variable "hosts" {
  description = "Ingress hosts served by this WordPress instance."
  type        = list(string)
}

variable "wordpress_update_strategy" {
  description = "Deployment update strategy. Use Recreate when the files PVC cannot attach to multiple nodes."
  type        = string
  default     = "RollingUpdate"

  validation {
    condition     = contains(["RollingUpdate", "Recreate"], var.wordpress_update_strategy)
    error_message = "wordpress_update_strategy must be RollingUpdate or Recreate."
  }
}

variable "upload_max_filesize_mb" {
  description = "Optional PHP file upload limit in MiB. Requests get 16 MiB of multipart overhead allowance."
  type        = number
  default     = null

  validation {
    condition     = var.upload_max_filesize_mb == null ? true : (var.upload_max_filesize_mb > 0 && floor(var.upload_max_filesize_mb) == var.upload_max_filesize_mb)
    error_message = "upload_max_filesize_mb must be a positive integer or null."
  }
}

variable "db_password" {
  description = "MariaDB application user password."
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "MariaDB root password."
  type        = string
  sensitive   = true
}

variable "files_size" {
  description = "WordPress files PVC size."
  type        = string
}

variable "db_size" {
  description = "MariaDB PVC size."
  type        = string
}

variable "restore_generation" {
  description = "Set to 0 to disable restore jobs. Bump to create new restore jobs."
  type        = number
  default     = 0
}

variable "restore_backup_pvc_name" {
  description = "PVC containing backup files when restore_generation is greater than 0."
  type        = string
  default     = null
}

variable "restore_backup_path" {
  description = "Directory under restore_backup_pvc_name containing files.tar.gz and db.sql.gz."
  type        = string
  default     = null
}

variable "restore_strip_components" {
  description = "Number of leading path components to strip from files.tar.gz during restore."
  type        = number
  default     = 0
}

variable "restore_s3_backup_path" {
  description = "S3 object prefix containing files.tar.gz and db.sql.gz. Set null to skip creating the manual restore CronJob."
  type        = string
  default     = null
}

variable "backup_s3_site_prefix" {
  description = "S3 prefix used for automatic backups of this WordPress instance."
  type        = string
}

variable "tls_enabled" {
  description = "Enable cert-manager TLS on the ingress after public DNS points to the cluster."
  type        = bool
  default     = false
}

variable "cluster_issuer_name" {
  description = "cert-manager ClusterIssuer name used when tls_enabled is true."
  type        = string
  default     = "letsencrypt-prod"
}
