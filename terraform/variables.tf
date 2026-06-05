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

variable "bootstrap_revision" {
  description = "Bump to trigger a new bootstrap run."
  type        = number
  default     = 1
  nullable    = false
}

variable "git_token" {
  description = "Git PAT for HTTPS authentication (e.g. for GitLab). Can be omitted for public repositories or when using a GitHub App."
  sensitive   = true
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the cluster directory under clusters/ (e.g. staging, prod-eu)."
  type        = string
  nullable    = false
}
variable "github_app_id" {
  description = "GitHub App ID."
  type        = string
  default     = ""
}

variable "github_app_installation_owner" {
  description = "GitHub App Installation Owner."
  type        = string
  default     = ""
}

variable "github_app_pem" {
  description = "The contents of the GitHub App private key PEM file."
  sensitive   = true
  type        = string
  default     = ""
}
