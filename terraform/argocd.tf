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
  version          = "7.8.26" # check https://artifacthub.io/packages/helm/argo/argo-cd for latest
  create_namespace = true

  values = [file("${path.module}/argocd-values.yaml")]

  depends_on = [
    infomaniak_kaas_instance_pool.workers,
    helm_release.nginx_ingress
  ]
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

resource "cloudflare_record" "argocd" {
  zone_id = var.cloudflare_zone_id
  name    = "argocd"
  # IP read directly from the Ingress status — no temp file needed
  value   = kubernetes_ingress_v1.argocd.status.0.load_balancer.0.ingress.0.ip
  type    = "A"
  proxied = true
}