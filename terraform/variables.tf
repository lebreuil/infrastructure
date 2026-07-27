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

variable "domain" {
  description = "Base domain for all services (e.g. your-domain.com). A wildcard certificate will be issued for *.your-domain.com"
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

## cert-manager related variables

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate expiry notifications"
  type        = string
}

## openbao related variables

variable "openbao_root_token" {
  description = "Root token for the OpenBao instance"
  type        = string
  sensitive   = true
}

