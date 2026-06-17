# Deploys the F5 NGINX Ingress Controller using the official Helm chart
# from the OCI registry.
#
# Replaces the community ingress-nginx controller (EOL March 2026) with
# the actively maintained F5/NGINX Inc. successor.
#
# The controller runs entirely on our dedicated worker nodes with no
# impact on other tenants of the shared Infomaniak cluster.
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "oci://ghcr.io/nginx/charts"
  chart            = "nginx-ingress"
  namespace        = "nginx-ingress"
  version          = "2.6.0"  # corresponds to NGINX Ingress Controller 5.5.0
  create_namespace = true

  values = [file("${path.module}/nginx-values.yaml")]

  depends_on = [infomaniak_kaas_instance_pool.workers]
}
