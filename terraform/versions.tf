
terraform {
  # Ensure the use of a compatible Terraform version
  required_version = ">= 0.14.0"

  required_providers {

    # Define the Infomaniak terraform provider
    infomaniak = {
      source = "Infomaniak/infomaniak"
    }

    # Add to main.tf required_providers
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }

    # Define the kubernetes terraform provider
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    # Define the helm terraform provider
    # add to downgrade to 3.0.2 to avoid the Helm 3.18.5 schema validation regression
    # where remote $ref URLs in values.schema.json are incorrectly rejected with "invalid file url".
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
    # Define the kubectl terraform provider
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }

    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

