
# --- netbox ---

resource "kubernetes_namespace_v1" "netbox" {
  metadata {
    name = "netbox"
  }
}

# Used by External Secrets Operator's SecretStore to authenticate to OpenBao.
# It is deliberately separate from the NetBox workload service account.
resource "kubernetes_service_account_v1" "netbox_secret_sync" {
  metadata {
    name      = "netbox-secret-sync"
    namespace = kubernetes_namespace_v1.netbox.metadata[0].name
  }

  automount_service_account_token = true
}

# ESO must be able to create a token only for the service account referenced by
# this namespace's SecretStore. The controller's other permissions come from
# its namespace-scoped Helm RBAC.
resource "kubernetes_role_v1" "netbox_secret_sync_token" {
  metadata {
    name      = "netbox-secret-sync-token"
    namespace = kubernetes_namespace_v1.netbox.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account_v1.netbox_secret_sync.metadata[0].name]
    verbs          = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "delete", "patch"]
  }

  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["secretstores/status", "secretstores/finalizers", "externalsecrets", "externalsecrets/status", "externalsecrets/finalizers"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "netbox_secret_sync_token" {
  metadata {
    name      = "netbox-secret-sync-token"
    namespace = kubernetes_namespace_v1.netbox.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.netbox_secret_sync_token.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets-controller"
    namespace = "external-secrets"
  }

  depends_on = [helm_release.external_secrets]
}

# ============================================================
# OpenBao Application Namespaces
# Each application gets its own isolated OpenBao namespace.
# The application team manages their secrets entirely within
# their namespace — they cannot access other namespaces.
# ============================================================

resource "vault_namespace" "netbox" {
  provider = vault.terraform
  path     = "netbox"
}

# KV secrets engine within the NetBox namespace
resource "vault_mount" "netbox_kv" {
  provider    = vault.terraform
  namespace   = vault_namespace.netbox.path
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for NetBox application secrets"

  depends_on = [vault_namespace.netbox]
}

# Kubernetes auth backend within the NetBox namespace
resource "vault_auth_backend" "netbox_kubernetes" {
  provider    = vault.terraform
  namespace   = vault_namespace.netbox.path
  type        = "kubernetes"
  description = "Kubernetes auth for NetBox pod service account authentication"

  depends_on = [vault_namespace.netbox]
}


resource "vault_kubernetes_auth_backend_config" "netbox" {
  provider               = vault.terraform
  namespace              = vault_namespace.netbox.path
  backend                = vault_auth_backend.netbox_kubernetes.path
  kubernetes_host        = "https://kubernetes.default.svc.cluster.local"
  disable_iss_validation = true

  depends_on = [vault_auth_backend.netbox_kubernetes]
}

# Read-only policy for the NetBox SecretStore — within NetBox namespace
resource "vault_policy" "netbox_read" {
  provider  = vault.terraform
  namespace = vault_namespace.netbox.path
  name      = "netbox-read"
  policy    = <<-EOT
    path "secret/data/config" {
      capabilities = ["read"]
    }
    path "secret/metadata/config" {
      capabilities = ["read"]
    }
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT

  depends_on = [vault_namespace.netbox]
}

# Write policy for the application team — within NetBox namespace
resource "vault_policy" "netbox_write" {
  provider  = vault.terraform
  namespace = vault_namespace.netbox.path
  name      = "netbox-write"
  policy    = <<-EOT
    path "secret/data/*" {
      capabilities = ["create", "update", "read", "list"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT

  depends_on = [vault_namespace.netbox]
}

# This role, the bound service account, and the token permissions are all
# platform-managed so application teams cannot grant themselves other OpenBao
# policies or namespaces.
resource "vault_kubernetes_auth_backend_role" "netbox_secret_sync" {
  provider                         = vault.terraform
  namespace                        = vault_namespace.netbox.path
  backend                          = vault_auth_backend.netbox_kubernetes.path
  role_name                        = "netbox-secret-sync"
  bound_service_account_names      = [kubernetes_service_account_v1.netbox_secret_sync.metadata[0].name]
  bound_service_account_namespaces = [kubernetes_namespace_v1.netbox.metadata[0].name]
  token_policies                   = [vault_policy.netbox_read.name]
  token_ttl                        = 3600

  depends_on = [
    kubernetes_service_account_v1.netbox_secret_sync,
    vault_auth_backend.netbox_kubernetes,
    vault_policy.netbox_read,
  ]
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
