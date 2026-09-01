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
