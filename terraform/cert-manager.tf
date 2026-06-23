# # Deploys cert-manager to automate TLS certificate issuance and renewal.
# #
# # cert-manager watches Certificate resources and automatically requests,
# # renews, and stores certificates as Kubernetes Secrets, which are then
# # referenced by the Cilium Gateway for TLS termination.
# resource "helm_release" "cert_manager" {
#   name             = "cert-manager"
#   repository       = "https://charts.jetstack.io"
#   chart            = "cert-manager"
#   namespace        = "cert-manager"
#   version          = "v1.17.2"
#   create_namespace = true

#   values = [file("${path.module}/cert-manager-values.yaml")]

#   depends_on = [infomaniak_kaas_instance_pool.workers]
# }

# # ClusterIssuer — tells cert-manager how to request certificates from
# # Let's Encrypt using the DNS-01 ACME challenge.
# #
# # DNS-01 is preferred over HTTP-01 because:
# #   - Works before the Gateway has an external IP assigned
# #   - Supports wildcard certificates (e.g. *.your-domain.com)
# #
# # This example uses Cloudflare as the DNS provider. Replace with your
# # own DNS provider — full list at:
# # https://cert-manager.io/docs/configuration/acme/dns01/

# # Cloudflare API token secret — used by cert-manager to create DNS
# # records for the DNS-01 ACME challenge.
# # Replace with the secret format required by your DNS provider.
# resource "kubernetes_secret_v1" "cloudflare_api_token" {
#   metadata {
#     name      = "cloudflare-api-token"
#     namespace = "cert-manager"
#   }

#   data = {
#     api-token = var.cloudflare_api_token
#   }

#   type       = "Opaque"
#   depends_on = [helm_release.cert_manager]
# }

# # kubectl_manifest is used instead of kubernetes_manifest because:
# #   - kubernetes_manifest validates the CRD against the API server at plan time,
# #     which fails if the cert-manager Helm chart hasn't been deployed yet
# #   - kubectl_manifest defers validation until apply time (after cert-manager is ready),
# #     avoiding the "no matches for kind" error during planning
# #   - Both are idempotent, but kubectl_manifest is better for resources that depend
# #     on CRDs created by other Helm charts in the same configuration
# resource "kubectl_manifest" "letsencrypt_issuer" {
#   yaml_body = yamlencode({
#     apiVersion = "cert-manager.io/v1"
#     kind       = "ClusterIssuer"
#     metadata = {
#       name = "letsencrypt-prod"
#     }
#     spec = {
#       acme = {
#         server = "https://acme-v02.api.letsencrypt.org/directory"
#         email  = var.letsencrypt_email
#         privateKeySecretRef = {
#           name = "letsencrypt-prod-account-key"
#         }
#         solvers = [{
#           dns01 = {
#             cloudflare = {
#               apiTokenSecretRef = {
#                 name = "cloudflare-api-token"
#                 key  = "api-token"
#               }
#             }
#           }
#         }]
#       }
#     }
#   })

#   depends_on = [
#     helm_release.cert_manager,
#     kubernetes_secret_v1.cloudflare_api_token
#   ]
# }
