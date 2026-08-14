# OpenBao configuration — Kubernetes auth backend, platform policies
# and per-application roles and DNS records.
#
# Provider:
#   Uses the dedicated Terraform token created by openbao-bootstrap.tf.
#   The root token is NOT used here. Apply openbao-bootstrap.tf first
#   to generate the terraform token before applying this file.
#
# Prerequisites:
#   2. openbao_terraform_token set in terraform.tfvars

provider "vault" {
  alias   = "terraform"
  address = "https://openbao.${var.domain}"
  token   = var.openbao_terraform_token
}

# ============================================================
# KV Secrets Engine
# ============================================================

resource "vault_mount" "kv" {
  provider    = vault.terraform
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for all platform and application secrets"
}

# ============================================================
# Kubernetes Auth Backend
# ============================================================

resource "vault_auth_backend" "kubernetes" {
  provider    = vault.terraform
  type        = "kubernetes"
  description = "Kubernetes auth for pod service account authentication"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  provider               = vault.terraform
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = "https://kubernetes.default.svc.cluster.local"
  disable_iss_validation = true
}

# ============================================================
# Platform Policies
# ============================================================

resource "vault_policy" "argocd" {
  provider = vault.terraform
  name     = "argocd"
  policy   = <<-EOT
    path "secret/data/platform/argocd-github-app" {
      capabilities = ["read"]
    }
  EOT
}

# ============================================================
# Platform Kubernetes Auth Roles
# ============================================================

resource "vault_kubernetes_auth_backend_role" "argocd" {
  provider                         = vault.terraform
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "argocd"
  bound_service_account_names      = ["argocd-repo-server"]
  bound_service_account_namespaces = ["argocd"]
  token_policies                   = [vault_policy.argocd.name]
  token_ttl                        = 3600
}
