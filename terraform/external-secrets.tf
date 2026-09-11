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
    },
    {
      name  = "rbac.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = "external-secrets-controller"
    },
    {
      name  = "processClusterExternalSecret"
      value = "false"
    },
    {
      name  = "processClusterStore"
      value = "false"
    },
    {
      name  = "processClusterGenerator"
      value = "false"
    },
    {
      name  = "processClusterPushSecret"
      value = "false"
    },
    {
      name  = "processPushSecret"
      value = "false"
    },
    {
      name  = "rbac.serviceAccountTokenCreate"
      value = "false"
    }
  ]

  depends_on = [infomaniak_kaas_instance_pool.workers]
}

# The controller discovers ESO resources cluster-wide and needs read-only
# informer access to target Secrets. It receives no cluster-wide Secret write
# permissions; each application namespace adds a namespaced Role/RoleBinding
# for Secret writes, status updates, and service-account token creation.
resource "kubernetes_cluster_role_v1" "external_secrets_controller" {
  metadata {
    name = "external-secrets-controller"
  }

  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["secretstores", "externalsecrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "serviceaccounts"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["generators.external-secrets.io"]
    resources  = ["generatorstates"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "external_secrets_controller" {
  metadata {
    name = "external-secrets-controller"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.external_secrets_controller.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets-controller"
    namespace = "external-secrets"
  }

  depends_on = [helm_release.external_secrets]
}
