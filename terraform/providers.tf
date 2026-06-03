
provider "flux" {
  kubernetes = {
    host                   = infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.server
    client_certificate     = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-certificate-data)
    client_key             = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-key-data)
    cluster_ca_certificate = base64decode(infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.certificate-authority-data)
  }
  git = {
    url = "https://github.com/${var.github_org}/${var.github_repository}.git"
    http = {
      username = "git" # This can be any string when using a personal access token
      password = var.github_token
    }
  }
}

provider "openstack" {
  cloud = "PCU-NG8KDXJ-dc3-a"
}

# Configure the Infomaniak Provider
provider "infomaniak" {
  host  = "https://api.infomaniak.com"
  token = var.infomaniak_token
}

provider "helm" {
  kubernetes = {
    host                   = infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.server
    cluster_ca_certificate = base64decode(infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.certificate-authority-data)
    client_certificate     = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-certificate-data)
    client_key             = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-key-data)
  }
}

provider "kubernetes" {
  host                   = infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.server
  cluster_ca_certificate = base64decode(infomaniak_kaas.kluster.kubeconfig.clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-certificate-data)
  client_key             = base64decode(infomaniak_kaas.kluster.kubeconfig.users[0].user.client-key-data)
}