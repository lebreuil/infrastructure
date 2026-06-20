

# Configure the Infomaniak Provider
provider "infomaniak" {
  host  = "https://api.infomaniak.com"
  token = var.infomaniak_token
}

# Uses the clouds.yaml configuration file for authentication.
# The cloud name matches the --os-cloud flag used with the OpenStack CLI.
# clouds.yaml is typically located at ~/.config/openstack/clouds.yaml
provider "openstack" {
  cloud = var.os_cloud
}

locals {
  kube_config = yamldecode(infomaniak_kaas.cluster.kubeconfig)
}

provider "helm" {
  kubernetes = {
    host                   = local.kube_config.clusters[0].cluster.server
    cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data)
    client_certificate     = base64decode(local.kube_config.users[0].user.client-certificate-data)
    client_key             = base64decode(local.kube_config.users[0].user.client-key-data)
  }
}

provider "kubernetes" {
  host                   = local.kube_config.clusters[0].cluster.server
  cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(local.kube_config.users[0].user.client-certificate-data)
  client_key             = base64decode(local.kube_config.users[0].user.client-key-data)
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubectl" {
  host                   = local.kube_config.clusters[0].cluster.server
  cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(local.kube_config.users[0].user.client-certificate-data)
  client_key             = base64decode(local.kube_config.users[0].user.client-key-data)
  load_config_file       = false
}

# port_forward replaces server_addr + password authentication.
# The provider connects via port-forward to the ArgoCD API server using
# the current kubeconfig context, avoiding the need to expose ArgoCD
# externally before Terraform can manage it. This also removes the
# chicken-and-egg problem where ArgoCD needed to be reachable at
# argocd.your-domain.com before the DNS record was created.
provider "argocd" {
  port_forward           = true
  port_forward_with_namespace = "argocd"
}
