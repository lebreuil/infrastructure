# Deploys OpenBao as cluster infrastructure for secret management.
#
# OpenBao is an open source fork of HashiCorp Vault (MPL-2.0) providing
# secret storage, dynamic secrets, and encryption as a service.
# It is a CNCF sandbox project under the OpenSSF.
#
# Architecture:
#   OpenBao runs as a single instance (standalone mode) on management
#   nodes. Secrets are stored on a persistent volume backed by OpenStack
#   Cinder. The web UI and API are exposed via NGINX Ingress at
#   openbao.your-domain.com.
#
#
# Post-deployment steps (one-time manual operations):
#   1. Initialize OpenBao — generates unseal keys and root token:
#      kubectl exec -n openbao openbao-0 -- bao operator init
#
#   2. Save the 5 unseal keys and root token securely (e.g. password
#      manager). These cannot be recovered if lost.
#
#   3. Unseal OpenBao (requires 3 of 5 keys by default):
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-1>
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-2>
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-3>
#
#   4. Verify OpenBao is unsealed:
#      kubectl exec -n openbao openbao-0 -- bao status
#
#   5. Configure OpenBao (auth methods, secret engines, policies)
#      via Argo CD from GitHub.
#
# Note: OpenBao must be manually unsealed after every pod restart.
# Consider configuring auto-unseal with OpenStack Barbican for
# production use.
resource "helm_release" "openbao" {
  name             = "openbao"
  repository       = "https://openbao.github.io/openbao-helm"
  chart            = "openbao"
  namespace        = "openbao"
  version          = "0.28.4"
  create_namespace = true

  values = [file("${path.module}/openbao-values.yaml")]

  depends_on = [
    infomaniak_kaas_instance_pool.management,
    helm_release.nginx_ingress,
    kubectl_manifest.letsencrypt_issuer
  ]
}

# OpenBao Ingress — defined separately from the Helm chart to follow
# the same pattern as all other platform and application services.
# TLS certificate is provisioned automatically by cert-manager.
resource "kubernetes_ingress_v1" "openbao" {
  wait_for_load_balancer = true

  metadata {
    name      = "openbao-ingress"
    namespace = "openbao"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.org/ssl-redirect"         = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["openbao.${var.domain}"]
      secret_name = "openbao-tls"
    }

    rule {
      host = "openbao.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "openbao-ui" # UI service
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


# OpenBao DNS record — platform-owned service, managed here
# alongside the OpenBao deployment rather than in openbao-config.tf
# since it is not an application onboarding concern.

resource "cloudflare_dns_record" "openbao" {
  zone_id = var.cloudflare_zone_id
  name    = "openbao"
  ttl     = 1
  type    = "A"
  comment = "OpenBao DNS record managed by Terraform"
  content = kubernetes_ingress_v1.openbao.status.0.load_balancer.0.ingress.0.ip
  proxied = true

  depends_on = [helm_release.nginx_ingress]
}
