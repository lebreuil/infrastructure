output "namespace" {
  value = kubernetes_namespace_v1.application.metadata[0].name
}

output "openbao_namespace" {
  value = vault_namespace.application.path
}
