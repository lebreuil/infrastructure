
terraform {
  # Ensure the use of a compatible Terraform version
  required_version = ">= 0.14.0"

  required_providers {

    # Define the Infomaniak terraform provider
    infomaniak = {
      source = "Infomaniak/infomaniak"
    }
    # Define the kubernetes terraform provider
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    # Define the helm terraform provider
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

