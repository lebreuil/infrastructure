terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    vault = {
      source                = "hashicorp/vault"
      configuration_aliases = [vault.terraform]
    }
  }
}
