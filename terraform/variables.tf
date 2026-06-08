# Github related variables

variable "git_url" {
  description = "URL of the Git repository."
  type        = string
  default     = ""
}

variable "git_ref" {
  description = "Reference of the Git repository."
  type        = string
  default     = ""
}

# Infomaniak related variables

variable "infomaniak_token" {
  description = "Token for the Infomaniak API   "
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "public_cloud_id" {
  description = "ID of the public cloud to use for the KaaS cluster"
  type        = number
}

variable "public_cloud_project_id" {
  description = "ID of the public cloud project to use for the KaaS cluster"
  type        = number
}

