
# ============================================================
# Per-Application Policies, Roles and DNS Records
# Add one block per application onboarded to the platform.
# resource "vault_policy" "your-app" { ... }
# resource "vault_kubernetes_auth_backend_role" "your-app" { ... }
# resource "cloudflare_record" "your-app" { ... }
# resource "cloudflare_zero_trust_access_application" "your-app" { ... }
# ============================================================

# --- app ---
# resource "vault_policy" "app" {
#   provider = vault.terraform
#   name     = "app"
#   policy   = <<-EOT
#     path "secret/data/app/*" {
#       capabilities = ["read"]
#     }
#   EOT
# }

# resource "vault_kubernetes_auth_backend_role" "app" {
#   provider                         = vault.terraform
#   backend                          = vault_auth_backend.kubernetes.path
#   role_name                        = "app"
#   bound_service_account_names      = ["app"]
#   bound_service_account_namespaces = ["app"]
#   token_policies                   = [vault_policy.app.name]
#   token_ttl                        = 3600
# }

# resource "kubernetes_namespace_v1" "app" {
#   metadata {
#     name = "app"
#   }
# }

# app Ingress — defined separately from the Helm chart to follow
# the same pattern as all other platform and application services.
# TLS certificate is provisioned automatically by cert-manager.
# resource "kubernetes_ingress_v1" "app" {
#   wait_for_load_balancer = true

#   metadata {
#     name      = "app-ingress"
#     namespace = "app"
#     annotations = {
#       "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
#       "nginx.org/ssl-redirect"         = "true"
#     }
#   }

#   spec {
#     ingress_class_name = "nginx"

#     tls {
#       hosts       = ["app.${var.domain}"]
#       secret_name = "app-tls"
#     }

#     rule {
#       host = "app.${var.domain}"
#       http {
#         path {
#           path      = "/"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = "openbao-ui" # UI service
#               port {
#                 number = 8200 # CHANGED from 80 to 8200
#               }
#             }
#           }
#         }
#       }
#     }
#   }

#   depends_on = [
#     helm_release.openbao,
#     kubectl_manifest.letsencrypt_issuer
#   ]
# }

# resource "cloudflare_dns_record" "app" {
#   zone_id = var.cloudflare_zone_id
#   name    = "app"
#   ttl = 1
#   type = "A"
#   comment = "app DNS record managed by Terraform"
#   content = kubernetes_ingress_v1.app.status.0.load_balancer.0.ingress.0.ip
#   proxied = true

#   depends_on = [helm_release.nginx_ingress]
# }

# resource "cloudflare_zero_trust_access_application" "app" {
#   account_id       = var.cloudflare_account_id
#   zone_id          = var.cloudflare_zone_id
#   name             = "app"
#   type             = "self_hosted"
#   session_duration = "8h"

#   destinations = [{
#     type = "public"
#     uri  = "app.${var.domain}"
#   }]

#   auto_redirect_to_identity = true
#   allowed_idps = [var.cloudflare_zero_trust_access_identity_provider]

#   policies = [{
#     id = data.cloudflare_zero_trust_access_policy.my_user.id
#   }]
# }


# --- Add new applications below following the same pattern ---

# --- podinfo ---

# Podinfo Ingress — routes external traffic to the podinfo service.
# TLS certificate is provisioned automatically by cert-manager.
resource "kubernetes_ingress_v1" "podinfo" {
  wait_for_load_balancer = true

  metadata {
    name      = "podinfo-ingress"
    namespace = "podinfo"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.org/ssl-redirect"         = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["podinfo.${var.domain}"]
      secret_name = "podinfo-tls"
    }

    rule {
      host = "podinfo.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "podinfo"
              port {
                number = 9898
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.nginx_ingress,
    kubectl_manifest.letsencrypt_issuer
  ]
}

resource "cloudflare_dns_record" "podinfo" {
  zone_id = var.cloudflare_zone_id
  name    = "podinfo"
  ttl     = 1
  type    = "A"
  comment = "podinfo DNS record managed by Terraform"
  content = kubernetes_ingress_v1.podinfo.status.0.load_balancer.0.ingress.0.ip
  proxied = true

  depends_on = [helm_release.nginx_ingress]
}

resource "cloudflare_zero_trust_access_application" "podinfo" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = "Podinfo"
  type             = "self_hosted"
  session_duration = "8h"

  destinations = [{
    type = "public"
    uri  = "podinfo.${var.domain}"
  }]

  auto_redirect_to_identity = true
  allowed_idps              = [var.cloudflare_zero_trust_access_identity_provider]

  policies = [{
    id = data.cloudflare_zero_trust_access_policy.my_user.id
  }]
}

# --- netbox ---

resource "kubernetes_namespace_v1" "netbox" {
  metadata {
    name = "netbox"
  }
}

resource "vault_policy" "netbox" {
  provider = vault.terraform
  name     = "netbox"
  policy   = <<-EOT
    path "secret/data/netbox/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "netbox" {
  provider                         = vault.terraform
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "netbox"
  bound_service_account_names      = ["netbox"]
  bound_service_account_namespaces = ["netbox"]
  token_policies                   = [vault_policy.netbox.name]
  token_ttl                        = 3600
}

# netbox Ingress — defined separately from the Helm chart to follow

resource "kubernetes_ingress_v1" "netbox" {
  wait_for_load_balancer = true

  metadata {
    name      = "netbox-ingress"
    namespace = "netbox"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.org/ssl-redirect"         = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["netbox.${var.domain}"]
      secret_name = "netbox-tls"
    }

    rule {
      host = "netbox.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "netbox-ui" # UI service
              port {
                number = 8200 # CHANGED from 80 to 8200
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.openbao,
    kubectl_manifest.letsencrypt_issuer
  ]
}

resource "cloudflare_dns_record" "netbox" {
  zone_id = var.cloudflare_zone_id
  name    = "netbox"
  ttl     = 1
  type    = "A"
  comment = "netbox DNS record managed by Terraform"
  content = kubernetes_ingress_v1.netbox.status.0.load_balancer.0.ingress.0.ip
  proxied = true

  depends_on = [helm_release.nginx_ingress]
}

resource "cloudflare_zero_trust_access_application" "netbox" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = "netbox"
  type             = "self_hosted"
  session_duration = "8h"

  destinations = [{
    type = "public"
    uri  = "netbox.${var.domain}"
  }]

  auto_redirect_to_identity = true
  allowed_idps              = [var.cloudflare_zero_trust_access_identity_provider]

  policies = [{
    id = data.cloudflare_zero_trust_access_policy.my_user.id
  }]
}