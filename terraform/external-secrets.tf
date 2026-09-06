# External Secrets Operator (ESO) is platform infrastructure. Application
# repositories declare ExternalSecret resources; ESO reconciles the resulting
# Kubernetes Secret from the external source of truth (OpenBao).
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.10.0"
  namespace        = "external-secrets"
  create_namespace = true

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]

  depends_on = [infomaniak_kaas_instance_pool.workers]
}
