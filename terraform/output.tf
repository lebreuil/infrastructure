output "kubeconfig" {
  value     = infomaniak_kaas.kluster.kubeconfig
  sensitive = true
}
