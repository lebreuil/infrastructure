
terraform {
  # Ensure the use of a compatible Terraform version
  required_version = ">= 0.14.0"

  # backend "s3" {
  #   bucket = "tf-state"
  #   key    = "k8s.tfstate"
  #   region = "us-east-1"
  #   endpoints = {
  #     s3 = "https://s3.pub1.infomaniak.cloud/"
  #   }
  # }

  required_providers {
    # Define OpenStack terraform provider
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0.0"
    }
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

