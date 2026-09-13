variable "applications" {
  description = "Applications requiring platform namespace, secret sync, OpenBao, and ingress resources."
  type = map(object({
    display_name      = string
    namespace         = string
    hostname          = string
    service_name      = string
    service_port      = number
    openbao_namespace = string
    github_team       = string
  }))
  default = {
    netbox = {
      display_name      = "NetBox"
      github_team       = "netbox"
      namespace         = "netbox"
      hostname          = "netbox.famillelebreuil.net"
      service_name      = "netbox"
      service_port      = 80
      openbao_namespace = "netbox"
    }
  }
}

module "application" {
  for_each = var.applications

  source = "./modules/application"

  name                = each.key
  display_name        = each.value.display_name
  namespace           = each.value.namespace
  hostname            = each.value.hostname
  service_name        = each.value.service_name
  service_port        = each.value.service_port
  openbao_namespace   = each.value.openbao_namespace
  github_team         = each.value.github_team
  github_organization = var.github_organization

  cloudflare_account_id                          = var.cloudflare_account_id
  cloudflare_zone_id                             = var.cloudflare_zone_id
  cloudflare_zero_trust_access_identity_provider = var.cloudflare_zero_trust_access_identity_provider
  cloudflare_access_policy_id                    = var.cloudflare_access_policy_id

  providers = {
    vault.terraform = vault.terraform
  }

  depends_on = [
    helm_release.external_secrets,
    helm_release.nginx_ingress,
    helm_release.openbao,
    kubectl_manifest.letsencrypt_issuer,
  ]
}

check "unique_application_hostnames" {
  assert {
    condition     = length(distinct([for application in var.applications : application.hostname])) == length(var.applications)
    error_message = "Application hostnames must be unique."
  }
}
