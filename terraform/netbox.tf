# Kubernetes Secret containing all NetBox sensitive credentials.
#
# Referenced by the NetBox Helm chart via existingSecret to avoid
# storing credentials in the Argo CD Application or values file.
#
# Keys required by the chart:
#   secret_key          - Django secret key (long random string)
#   superuser_password  - Initial admin password
#   superuser_api_token - Initial admin API token
#   postgresql-password - PostgreSQL password
#   redis-password      - Redis password
resource "kubernetes_secret_v1" "netbox_secrets" {
  metadata {
    name      = "netbox-secrets"
    namespace = "netbox"
  }

  data = {
    secret_key          = var.netbox_secret_key
    superuser_password  = var.netbox_superuser_password
    superuser_api_token = var.netbox_superuser_api_token
    postgresql-password = var.netbox_postgresql_password
    redis-password      = var.netbox_redis_password
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
# Uses the Argo CD Terraform provider rather than kubernetes_manifest
# to avoid CRD validation errors during terraform plan (the Application
# CRD only exists after Argo CD is installed).
resource "argocd_application" "netbox" {
  metadata {
    name      = "netbox"
    namespace = "argocd"
  }

  # wait = true replaces the previous depends_on workaround,
  # ensuring Terraform waits for NetBox to be fully synced and healthy
  # before considering the resource created.
  wait = true

  spec {
    project = "default"

    source {
      repo_url        = "ghcr.io/netbox-community/netbox-chart"
      chart           = "netbox"
      target_revision = "8.3.18"

      helm {
        # values_object replaces values (raw YAML string)
        # for cleaner HCL-native value passing
        values = templatefile("${path.module}/netbox-values.yaml", {
          domain             = var.domain
          netbox_admin_email = var.netbox_admin_email
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

resource "cloudflare_record" "netbox" {
  zone_id = var.cloudflare_zone_id
  name    = "netbox"
  value   = kubernetes_ingress_v1.netbox.status.0.load_balancer.0.ingress.0.ip
  type    = "A"
  proxied = true
}
