resource "kubernetes_namespace_v1" "application" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account_v1" "secret_sync" {
  metadata {
    name      = "${var.name}-secret-sync"
    namespace = kubernetes_namespace_v1.application.metadata[0].name
  }

  automount_service_account_token = true
}

resource "kubernetes_role_v1" "secret_sync_token" {
  metadata {
    name      = "${var.name}-secret-sync-token"
    namespace = kubernetes_namespace_v1.application.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account_v1.secret_sync.metadata[0].name]
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

resource "kubernetes_role_binding_v1" "secret_sync_token" {
  metadata {
    name      = "${var.name}-secret-sync-token"
    namespace = kubernetes_namespace_v1.application.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.secret_sync_token.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets-controller"
    namespace = "external-secrets"
  }
}

resource "vault_namespace" "application" {
  provider = vault.terraform
  path     = var.openbao_namespace
}

resource "vault_mount" "kv" {
  provider    = vault.terraform
  namespace   = vault_namespace.application.path
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for ${var.display_name} application secrets"
}

resource "vault_auth_backend" "kubernetes" {
  provider    = vault.terraform
  namespace   = vault_namespace.application.path
  type        = "kubernetes"
  description = "Kubernetes auth for ${var.display_name} pod service account authentication"
}

resource "vault_kubernetes_auth_backend_config" "application" {
  provider               = vault.terraform
  namespace              = vault_namespace.application.path
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = "https://kubernetes.default.svc.cluster.local"
  disable_iss_validation = true
}

resource "vault_policy" "read" {
  provider  = vault.terraform
  namespace = vault_namespace.application.path
  name      = "${var.name}-read"
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
}

resource "vault_policy" "write" {
  provider  = vault.terraform
  namespace = vault_namespace.application.path
  name      = "${var.name}-write"
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
}

resource "vault_github_auth_backend" "github" {
  provider      = vault.terraform
  namespace     = vault_namespace.application.path
  path          = "github"
  organization  = var.github_organization
  description   = "GitHub authentication for ${var.display_name} application team"
  token_ttl     = 3600
  token_max_ttl = 14400
}

resource "vault_github_team" "application" {
  provider  = vault.terraform
  namespace = vault_namespace.application.path
  backend   = vault_github_auth_backend.github.path
  team      = var.github_team
  policies  = [vault_policy.write.name]
}

resource "vault_kubernetes_auth_backend_role" "secret_sync" {
  provider                         = vault.terraform
  namespace                        = vault_namespace.application.path
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "${var.name}-secret-sync"
  bound_service_account_names      = [kubernetes_service_account_v1.secret_sync.metadata[0].name]
  bound_service_account_namespaces = [kubernetes_namespace_v1.application.metadata[0].name]
  token_policies                   = [vault_policy.read.name]
  token_ttl                        = 3600
}

resource "kubernetes_ingress_v1" "application" {
  wait_for_load_balancer = true

  metadata {
    name      = "${var.name}-ingress"
    namespace = var.namespace
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.org/ssl-redirect"         = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [var.hostname]
      secret_name = "${var.name}-tls"
    }

    rule {
      host = var.hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.service_name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}

resource "cloudflare_dns_record" "application" {
  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(var.hostname, ".${data.cloudflare_zone.zone.name}")
  ttl     = 1
  type    = "A"
  comment = "${var.name} DNS record managed by Terraform"
  content = kubernetes_ingress_v1.application.status.0.load_balancer.0.ingress.0.ip
  proxied = true
}

data "cloudflare_zone" "zone" {
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_zero_trust_access_application" "application" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = var.access_name
  type             = "self_hosted"
  session_duration = "8h"

  destinations = [{
    type = "public"
    uri  = var.hostname
  }]

  auto_redirect_to_identity = true
  allowed_idps              = [var.cloudflare_zero_trust_access_identity_provider]

  policies = [{
    id = var.cloudflare_access_policy_id
  }]
}
