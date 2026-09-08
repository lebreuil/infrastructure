# Deploys Argo CD on the Infomaniak managed Kubernetes cluster using the
# official Helm chart.
#
# Context:
#   Argo CD is deployed in its own namespace following best practices.
#   The installation depends on worker nodes being available to schedule pods.
#
# After deployment, retrieve the initial admin password with:
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath="{.data.password}" | base64 -d

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "10.1.4" # check https://artifacthub.io/packages/helm/argo/argo-cd for latest
  create_namespace = true

  values = [file("${path.module}/argocd-values.yaml")]

  depends_on = [
    infomaniak_kaas_instance_pool.workers,
    helm_release.nginx_ingress
  ]
}

resource "kubernetes_service_account_v1" "argocd_secret_sync" {
  metadata {
    name      = "argocd-secret-sync"
    namespace = "argocd"
  }

  automount_service_account_token = true

  depends_on = [helm_release.argocd]
}

resource "kubernetes_role_v1" "argocd_secret_sync" {
  metadata {
    name      = "argocd-secret-sync"
    namespace = "argocd"
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account_v1.argocd_secret_sync.metadata[0].name]
    verbs          = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "delete", "patch"]
  }

  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["secretstores/status", "secretstores/finalizers", "externalsecrets/status", "externalsecrets/finalizers"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "argocd_secret_sync" {
  metadata {
    name      = "argocd-secret-sync"
    namespace = "argocd"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argocd_secret_sync.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets-controller"
    namespace = "external-secrets"
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "argocd_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "openbao"
      namespace = "argocd"
    }
    spec = {
      provider = {
        vault = {
          server    = "https://openbao.${var.domain}"
          path      = "secret"
          version   = "v2"
          namespace = "platform"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "argocd-secret-sync"
              serviceAccountRef = {
                name = kubernetes_service_account_v1.argocd_secret_sync.metadata[0].name
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    kubernetes_service_account_v1.argocd_secret_sync,
    vault_kubernetes_auth_backend_role.argocd,
  ]
}

resource "kubectl_manifest" "argocd_external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "github-org-creds"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        name = "openbao"
        kind = "SecretStore"
      }
      target = {
        name           = "github-org-creds"
        creationPolicy = "Owner"
        template = {
          metadata = {
            labels = {
              "argocd.argoproj.io/secret-type" = "repo-creds"
            }
          }
          type = "Opaque"
          data = {
            type                    = "git"
            url                     = "https://github.com/${var.github_organization}"
            githubAppID             = "{{ .githubAppID }}"
            githubAppInstallationID = "{{ .githubAppInstallationID }}"
            githubAppPrivateKey     = "{{ .githubAppPrivateKey }}"
          }
        }
      }
      data = [
        {
          secretKey = "githubAppID"
          remoteRef = {
            key      = "argocd-github-app"
            property = "app-id"
          }
        },
        {
          secretKey = "githubAppInstallationID"
          remoteRef = {
            key      = "argocd-github-app"
            property = "installation-id"
          }
        },
        {
          secretKey = "githubAppPrivateKey"
          remoteRef = {
            key      = "argocd-github-app"
            property = "private-key"
          }
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.argocd_secret_store]
}

# cert-manager annotation automatically provisions and renews
# the TLS certificate for this Ingress via the letsencrypt-prod
# ClusterIssuer.
# Replaced kubectl_manifest with kubernetes_ingress_v1 from
# the hashicorp/kubernetes provider, which natively supports Ingress
# resources without CRD validation issues (Ingress is a core Kubernetes
# resource, not a CRD).
resource "kubernetes_ingress_v1" "argocd" {
  # Terraform waits for the LoadBalancer IP to be assigned before
  # considering this resource created. Eliminates the need for a
  # separate terraform_data wait mechanism.
  wait_for_load_balancer = true

  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.org/ssl-redirect"         = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["argocd.${var.domain}"]
      secret_name = "argocd-tls"
    }

    rule {
      host = "argocd.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    helm_release.nginx_ingress
  ]
}

# Argo CD DNS record — platform-owned service, managed here
# alongside the Argo CD deployment rather than in openbao-config.tf
# since it is not an application onboarding concern.

resource "cloudflare_dns_record" "argocd" {
  zone_id = var.cloudflare_zone_id
  name    = "argocd"
  ttl     = 1
  type    = "A"
  comment = "Argo CD DNS record managed by Terraform"
  content = kubernetes_ingress_v1.argocd.status.0.load_balancer.0.ingress.0.ip
  proxied = true

  depends_on = [helm_release.nginx_ingress]
}

# App of Apps — bootstraps the Argo CD application registry.
# Watches the applications-repo/applications/ directory and
# automatically registers any Application manifest added there.
# Applied once after Argo CD is deployed — self-managing thereafter.
resource "kubectl_manifest" "app_of_apps" {
  yaml_body = file("${path.module}/../gitops/app-of-apps.yaml")

  depends_on = [helm_release.argocd]
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = "argocd"
  type             = "self_hosted"
  session_duration = "8h"

  destinations = [{
    type = "public"
    uri  = "argocd.${var.domain}"
  }]

  auto_redirect_to_identity = true
  allowed_idps              = [var.cloudflare_zero_trust_access_identity_provider]

  policies = [{
    id = data.cloudflare_zero_trust_access_policy.my_user.id
  }]
}