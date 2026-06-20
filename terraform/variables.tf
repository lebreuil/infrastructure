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

variable "github_app_id" {
  description = "GitHub App ID."
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID."
  type        = string
  default     = ""
}

variable "github_app_pem" {
  description = "The contents of the GitHub App private key PEM file."
  sensitive   = true
  type        = string
  default     = ""
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate expiry notifications"
  type        = string
}

# OpenStack related variables
variable "os_cloud" {
  description = "OpenStack cloud name from clouds.yaml (matches --os-cloud CLI flag, e.g. PCP-NG8KDXJ-dc3-a)"
  type        = string
}

# Cloudflare related variables

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS-01 ACME challenge"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain, found in the Cloudflare dashboard"
  type        = string
}

variable "domain" {
  description = "Base domain for all services (e.g. your-domain.com). A wildcard certificate will be issued for *.your-domain.com"
  type        = string
}

# Netbox related variables

variable "netbox_secret_key" {
  description = "Django secret key for NetBox (long random string, min 50 chars)"
  type        = string
  sensitive   = true
}

variable "netbox_superuser_password" {
  description = "Initial NetBox admin password"
  type        = string
  sensitive   = true
}

variable "netbox_superuser_api_token" {
  description = "Initial NetBox admin API token (40 hex characters)"
  type        = string
  sensitive   = true
}

variable "netbox_postgresql_password" {
  description = "PostgreSQL password for NetBox"
  type        = string
  sensitive   = true
}

variable "netbox_redis_password" {
  description = "Redis password for NetBox"
  type        = string
  sensitive   = true
}

variable "netbox_admin_email" {
  description = "Email address for the NetBox admin superuser"
  type        = string
}
