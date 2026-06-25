# Kubernetes Secret containing all NetBox sensitive credentials.
#
# Referenced by the NetBox Helm chart via existingSecret to avoid
# storing credentials in the Argo CD Application or values file.
#
resource "kubernetes_secret_v1" "netbox_secrets" {
  metadata {
    name      = "netbox-secrets"
    namespace = "netbox"
  }

  data = {
    # Required — Django session encryption key (50+ random characters)
    secret_key = var.netbox_secret_key

    # superuser credentials
    password  = var.netbox_superuser_password
    username  = "admin"
    email     = var.netbox_admin_email
    api_token = var.netbox_superuser_api_token

    # Email password
    # Referenced by email.existingSecretKey: email-password
    email-password = var.netbox_email_password
  }

  type = "Opaque"

  depends_on = [kubernetes_manifest.netbox_namespace]
}

# Namespace for NetBox — created explicitly so the Secret above
# can be created before Argo CD deploys the Application.
resource "kubernetes_manifest" "netbox_namespace" {
  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "netbox"
    }
  }
}

# Argo CD Application resource — deploys NetBox via the official
# Helm chart from the OCI registry.
#
resource "argocd_application" "netbox" {
  metadata {
    name      = "netbox"
    namespace = "argocd"
  }

  # wait = true caused the resource to be tainted.
  # remove taint with: terraform state untaint argocd_application.netbox
  wait = false

  spec {
    project = "default"

    source {
      repo_url        = "ghcr.io/netbox-community/netbox-chart"
      chart           = "netbox"
      target_revision = "8.3.18"

      helm {
        values = templatefile("${path.module}/netbox-values.yaml", {
          domain = var.domain
        })
      }
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "netbox"
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["CreateNamespace=false"]
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.netbox_secrets
  ]
}

# Replaced kubectl_manifest with kubernetes_ingress_v1.
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
              name = "netbox"
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
    argocd_application.netbox,
    helm_release.nginx_ingress
  ]
}

resource "cloudflare_dns_record" "netbox" {
  zone_id = var.cloudflare_zone_id
  name    = "netbox"
  content = kubernetes_ingress_v1.netbox.status.0.load_balancer.0.ingress.0.ip
  type    = "A"
  ttl     = 1
  proxied = true
}
