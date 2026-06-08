
locals {
  has_git_token  = var.git_token != ""
  has_github_app = var.github_app_id != ""
  git_auth_secret = local.has_git_token || local.has_github_app ? yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name = "flux-system"
    }
    type = "Opaque"
    stringData = merge(
      local.has_git_token ? {
        username = "git"
        password = var.git_token
      } : {},
      local.has_github_app ? {
        githubAppID                = var.github_app_id
        githubAppInstallationID = var.github_app_installation_id
        githubAppPrivateKey        = var.github_app_pem
      } : {},
    )
  }) : ""
}


module "flux_operator_bootstrap" {
  depends_on = [infomaniak_kaas.cluster]
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"

  revision = var.bootstrap_revision

  gitops_resources = {
    instance_yaml = file("${path.root}/../clusters/${var.cluster_name}/flux-system/flux-instance.yaml")
  }

  managed_resources = {
    secrets_yaml = local.git_auth_secret
  }
}