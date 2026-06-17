
# # Enables Kubernetes Gateway API support in Cilium by patching the cilium-config ConfigMap.
# #
# # Context:
# #   Cilium is installed and managed by Infomaniak as a cluster addon via Helm
# #   (release: pck-ec9h9pa-addon-cilium, chart: cilium-1.19.1).
# # Prerequisites:
# #   Gateway API CRDs must be installed before applying this resource.
# # kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# # Fetch manifest from a URL
# data "http" "gateway_api_standard_install" {
#   url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/experimental-install.yaml"
# }

# # Split the multi-document YAML
# data "kubectl_file_documents" "gateway_api" {
#   content = data.http.gateway_api_standard_install.response_body
# }

# # Apply all resources
# resource "kubectl_manifest" "gateway_api" {
#   for_each  = data.kubectl_file_documents.gateway_api.manifests
#   yaml_body = each.value

#   server_side_apply = true
#   wait              = true
# }


# #   To avoid conflicts with Infomaniak's Helm release ownership, we patch only
# #   the specific Gateway API keys rather than managing the full helm_release resource.
# #
# # Keys:
# #   enable-gateway-api             - activates the Gateway API controller in Cilium
# #   enable-gateway-api-secrets-sync - syncs TLS secrets into the cilium-secrets namespace,
# #                                    required for HTTPS listeners on Gateway resources

# resource "kubernetes_config_map_v1_data" "cilium_gateway_api" {
#   metadata {
#     name      = "cilium-config"
#     namespace = "kube-system"
#   }

#   data = {
#     "enable-gateway-api"              = "true"
#     "enable-gateway-api-secrets-sync" = "true"
#   }

#   force = true
#   depends_on = [kubectl_manifest.gateway_api]
# }

# # a single Secret
# # is shared across all services via the shared Gateway.
# # Stored in kube-system alongside the shared Gateway.

# resource "kubectl_manifest" "wildcard_certificate" {
#   yaml_body = yamlencode({
#     apiVersion = "cert-manager.io/v1"
#     kind       = "Certificate"
#     metadata = {
#       name      = "shared-tls"
#       namespace = "kube-system"
#     }
#     spec = {
#       secretName = "shared-tls"
#       issuerRef = {
#         name = "letsencrypt-prod"
#         kind = "ClusterIssuer"
#       }
#       dnsNames = [
#         "*.${var.domain}", # covers all subdomains e.g. argocd.your-domain.com
#         var.domain         # covers the apex domain
#       ]
#     }
#   })

#   depends_on = [kubectl_manifest.letsencrypt_issuer]
# }

# # ============================================================
# # CHANGED — replaced kubernetes_manifest with kubectl_manifest
# # to avoid CRD validation errors during plan/apply/destroy
# # when Gateway API CRDs are not yet installed or have been removed.
# # ============================================================

# # A single Cilium Gateway results in a single Octavia Load
# # Balancer and Floating IP on Infomaniak, regardless of how
# # many services are exposed through it.
# # allowedRoutes.namespaces.from = "All" allows HTTPRoutes from
# # any namespace (e.g. argocd, monitoring) to attach to it.
# resource "kubectl_manifest" "shared_gateway" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: Gateway
#     metadata:
#       name: shared-gateway
#       namespace: kube-system
#     spec:
#       gatewayClassName: cilium
#       listeners:
#         - name: https
#           protocol: HTTPS
#           port: 443
#           tls:
#             mode: Terminate
#             certificateRefs:
#               - kind: Secret
#                 name: shared-tls
#           allowedRoutes:
#             namespaces:
#               from: All
#   YAML

#   server_side_apply = true
#   wait              = true

#   depends_on = [kubectl_manifest.wildcard_certificate]
# }

# # Reads the LoadBalancer Service created by Cilium for the shared Gateway
# # to retrieve the external Floating IP assigned by OpenStack CCM.
# # The Service name mirrors the Gateway name by Cilium convention.
# # CHANGED — depends_on updated to reference kubectl_manifest.shared_gateway
# data "kubernetes_service_v1" "shared_gateway" {
#   metadata {
#     name      = "cilium-gateway-shared-gateway"
#     namespace = "kube-system"
#   }

#   depends_on = [kubectl_manifest.shared_gateway]
# }