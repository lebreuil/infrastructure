# Wildcard DNS record pointing all subdomains to the shared NGINX
# ingress Floating IP.
#
# Covers all current and future services deployed via Argo CD without
# The NGINX Ingress Controller routes traffic to the correct service
# based on the Host header via Ingress resources managed by Argo CD.
# ttl has to be set to one when record is proxied, otherwise Cloudflare will return an error.
resource "cloudflare_dns_record" "wildcard" {
  zone_id    = var.cloudflare_zone_id
  name       = "*"
  content    = kubernetes_ingress_v1.argocd.status.0.load_balancer.0.ingress.0.ip
  type       = "A"
  proxied    = true
  ttl        = 1
  depends_on = [helm_release.nginx_ingress]
}
