# Deploys the F5 NGINX Ingress Controller using the official Helm chart
# from the OCI registry.
# Replaces the community ingress-nginx controller (EOL March 2026) with
# the actively maintained F5/NGINX Inc. successor.
# Provider version has to be fixed
# https://github.com/hashicorp/terraform-provider-helm/issues/1798
resource "helm_release" "nginx_ingress" {
  name                       = "nginx-ingress"
  repository                 = "oci://ghcr.io/nginx/charts"
  chart                      = "nginx-ingress"
  namespace                  = "nginx-ingress"
  version                    = "2.6.0"
  create_namespace           = true
  disable_openapi_validation = true
  timeout                    = 600

  values = [templatefile("${path.module}/nginx-values.yaml", {
    domain    = var.domain,
    subnet_id = local.subnet_id
    cloudflare_ipv4_cidrs = data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs
  })]

  depends_on = [data.cloudflare_ip_ranges.cloudflare, infomaniak_kaas_instance_pool.workers]
}
