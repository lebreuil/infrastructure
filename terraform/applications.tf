variable "applications" {
  description = "Applications requiring platform namespace, secret sync, OpenBao, and ingress resources."
  type = map(object({
    display_name      = string
    access_name       = string
    namespace         = string
    hostname          = string
    service_name      = string
    service_port      = number
    openbao_namespace = string
    oidc_group        = string
    oidc_enabled      = bool
  }))
  default = {
    netbox = {
      display_name      = "NetBox"
      oidc_group        = "netbox"
      access_name       = "netbox"
      namespace         = "netbox"
      hostname          = "netbox.famillelebreuil.net"
      service_name      = "netbox"
      service_port      = 80
      openbao_namespace = "netbox"
      oidc_enabled      = true
    }
    podinfo = {
      display_name      = "Podinfo"
      access_name       = "Podinfo"
      oidc_group        = "podinfo"
      namespace         = "podinfo"
      hostname          = "podinfo.famillelebreuil.net"
      service_name      = "podinfo"
      service_port      = 9898
      openbao_namespace = "podinfo"
      oidc_enabled      = true
    }
    authentik = {
      display_name      = "Authentik"
      access_name       = "Authentik"
      namespace         = "authentik"
      hostname          = "auth.famillelebreuil.net"
      service_name      = "authentik-server"
      service_port      = 80
      openbao_namespace = "authentik"
      oidc_group        = "authentik"
      oidc_enabled      = false
    }
  }
}

module "application" {
  for_each = var.applications

  source = "./modules/application"

  name               = each.key
  display_name       = each.value.display_name
  namespace          = each.value.namespace
  hostname           = each.value.hostname
  service_name       = each.value.service_name
  service_port       = each.value.service_port
  openbao_namespace  = each.value.openbao_namespace
  oidc_group         = each.value.oidc_group
  oidc_enabled       = each.value.oidc_enabled && var.oidc_discovery_url != "" && var.oidc_client_id != "" && var.oidc_client_secret != ""
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  # OpenBao's UI callback for the per-namespace OIDC mount.
  oidc_allowed_redirect_uris = [
    "https://openbao.${var.domain}/ui/vault/auth/oidc/oidc/callback",
  ]
  access_name = each.value.access_name

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
