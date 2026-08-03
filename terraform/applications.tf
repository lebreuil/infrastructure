
# ============================================================
# Per-Application Policies, Roles and DNS Records
# Add one block per application onboarded to the platform.
# ============================================================

# --- NetBox ---
# resource "vault_policy" "netbox" {
#   provider = vault.terraform
#   name     = "netbox"
#   policy   = <<-EOT
#     path "secret/data/netbox/*" {
#       capabilities = ["read"]
#     }
#   EOT
# }

# resource "vault_kubernetes_auth_backend_role" "netbox" {
#   provider                         = vault.terraform
#   backend                          = vault_auth_backend.kubernetes.path
#   role_name                        = "netbox"
#   bound_service_account_names      = ["netbox"]
#   bound_service_account_namespaces = ["netbox"]
#   token_policies                   = [vault_policy.netbox.name]
#   token_ttl                        = 3600
# }

# resource "cloudflare_dns_record" "netbox" {
#   zone_id = var.cloudflare_zone_id
#   name    = "netbox"
#   ttl = 1
#   type = "A"
#   comment = "NetBox DNS record managed by Terraform"
#   content = kubernetes_ingress_v1.netbox.status.0.load_balancer.0.ingress.0.ip
#   proxied = true

#   depends_on = [helm_release.nginx_ingress]
# }


# --- Add new applications below following the same pattern ---
# resource "vault_policy" "your-app" { ... }
# resource "vault_kubernetes_auth_backend_role" "your-app" { ... }
# resource "cloudflare_record" "your-app" { ... }

resource "cloudflare_dns_record" "podinfo" {
  zone_id = var.cloudflare_zone_id
  name    = "podinfo"
  ttl = 1
  type = "A"
  comment = "OpenBao DNS record managed by Terraform"
  content = kubernetes_ingress_v1.openbao.status.0.load_balancer.0.ingress.0.ip
  proxied = true

  depends_on = [helm_release.nginx_ingress]
}