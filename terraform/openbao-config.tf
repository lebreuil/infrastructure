# ============================================================
# Platform namespace — for platform team secrets
# (GitHub App credentials etc.)
# ============================================================

resource "vault_namespace" "platform" {
  provider = vault.terraform
  path     = "platform"
}

resource "vault_mount" "platform_kv" {
  provider    = vault.terraform
  namespace   = vault_namespace.platform.path
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for platform secrets"

  depends_on = [vault_namespace.platform]
}

resource "vault_auth_backend" "platform_kubernetes" {
  provider    = vault.terraform
  namespace   = vault_namespace.platform.path
  type        = "kubernetes"
  description = "Kubernetes auth for platform service accounts"

  depends_on = [vault_namespace.platform]
}

resource "vault_kubernetes_auth_backend_config" "platform" {
  provider               = vault.terraform
  namespace              = vault_namespace.platform.path
  backend                = vault_auth_backend.platform_kubernetes.path
  kubernetes_host        = "https://kubernetes.default.svc.cluster.local"
  disable_iss_validation = true

  depends_on = [vault_auth_backend.platform_kubernetes]
}

# Argo CD policy — within platform namespace
resource "vault_policy" "argocd" {
  provider  = vault.terraform
  namespace = vault_namespace.platform.path
  name      = "argocd"
  policy    = <<-EOT
    path "secret/data/argocd-github-app" {
      capabilities = ["read"]
    }
    path "secret/metadata/argocd-github-app" {
      capabilities = ["read"]
    }
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT

  depends_on = [vault_namespace.platform]
}

resource "vault_kubernetes_auth_backend_role" "argocd" {
  provider                         = vault.terraform
  namespace                        = vault_namespace.platform.path
  backend                          = vault_auth_backend.platform_kubernetes.path
  role_name                        = "argocd-secret-sync"
  bound_service_account_names      = ["argocd-secret-sync"]
  bound_service_account_namespaces = ["argocd"]
  token_policies                   = [vault_policy.argocd.name]
  token_ttl                        = 3600

  depends_on = [
    vault_auth_backend.platform_kubernetes,
    vault_policy.argocd
  ]
}

resource "vault_policy" "platform_write" {
  provider  = vault.terraform
  namespace = vault_namespace.platform.path
  name      = "platform-write"
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
    path "sys/capabilities-self" {
      capabilities = ["update"]
    }
  EOT

  depends_on = [vault_namespace.platform]
}
