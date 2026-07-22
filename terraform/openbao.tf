# Deploys OpenBao as cluster infrastructure for secret management.
#
# OpenBao is an open source fork of HashiCorp Vault (MPL-2.0) providing
# secret storage, dynamic secrets, and encryption as a service.
# It is a CNCF sandbox project under the OpenSSF.
#
# Architecture:
#   OpenBao runs as a single instance (standalone mode) on management
#   nodes. Secrets are stored on a persistent volume backed by OpenStack
#   Cinder. The web UI and API are exposed via NGINX Ingress at
#   openbao.your-domain.com.
#
#
# Post-deployment steps (one-time manual operations):
#   1. Initialize OpenBao — generates unseal keys and root token:
#      kubectl exec -n openbao openbao-0 -- bao operator init
#
#   2. Save the 5 unseal keys and root token securely (e.g. password
#      manager). These cannot be recovered if lost.
#
#   3. Unseal OpenBao (requires 3 of 5 keys by default):
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-1>
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-2>
#      kubectl exec -n openbao openbao-0 -- bao operator unseal <key-3>
#
#   4. Verify OpenBao is unsealed:
#      kubectl exec -n openbao openbao-0 -- bao status
#
#   5. Configure OpenBao (auth methods, secret engines, policies)
#      via Argo CD from GitHub.
#
# Note: OpenBao must be manually unsealed after every pod restart.
# Consider configuring auto-unseal with OpenStack Barbican for
# production use.
resource "helm_release" "openbao" {
  name             = "openbao"
  repository       = "https://openbao.github.io/openbao-helm"
  chart            = "openbao"
  namespace        = "openbao"
  version          = "0.28.6"
  create_namespace = true

  values = [templatefile("${path.module}/openbao-values.yaml", {
    domain = var.domain
  })]

  depends_on = [
    infomaniak_kaas_instance_pool.management,
    helm_release.nginx_ingress,
    kubectl_manifest.letsencrypt_issuer
  ]
}