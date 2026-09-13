variable "name" {
  type        = string
  description = "Stable application identifier."
}

variable "display_name" {
  type        = string
  description = "Human-readable application name used in resource descriptions."
}

variable "namespace" {
  type        = string
  description = "Kubernetes and OpenBao namespace for the application."
}

variable "hostname" {
  type        = string
  description = "Public hostname routed to the application Service."
}

variable "service_name" {
  type        = string
  description = "Kubernetes Service name created by the application deployment."
}

variable "service_port" {
  type        = number
  description = "Kubernetes Service port exposed through the Ingress."
}

variable "openbao_namespace" {
  type        = string
  description = "OpenBao namespace used by the application's SecretStore."
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_zero_trust_access_identity_provider" {
  type = string
}

variable "cloudflare_access_policy_id" {
  type = string
}
