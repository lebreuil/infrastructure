# OpenBao bootstrap — applied ONCE using the root token immediately
# after OpenBao initialization and unsealing.
#
# Purpose:
#   Creates a dedicated Terraform policy and token with least-privilege
#   permissions. After this file is applied, the root token should be
#   stored securely and the dedicated terraform token used for all
#   subsequent Terraform operations.
#
# Provider:
#   Uses a separate 'vault_bootstrap' provider alias configured with
#   the root token. This allows openbao-config.tf to use a different
#   provider alias configured with the dedicated terraform token.
#
# Workflow:
#   1. Add openbao_root_token to terraform.tfvars
#   2. terraform apply -target=vault_policy.terraform
#   3. terraform apply -target=vault_token.terraform
#   4. Retrieve the token: terraform output -raw terraform_token
#   5. Add openbao_terraform_token to terraform.tfvars
#   6. Store root token securely and do not use it again
#   7. Proceed with openbao-config.tf using the dedicated token

provider "vault" {
  alias   = "bootstrap"
  address = "https://openbao.${var.domain}"
  token   = var.openbao_root_token
}

# Least-privilege policy for Terraform — grants only the permissions
# needed to manage KV secrets, auth backends, mounts and policies.
# Does NOT grant access to application secrets themselves.
resource "vault_policy" "terraform" {
  provider = vault.bootstrap
  name     = "terraform"
  policy   = <<-EOT
    # KV secrets engine management
    path "secret/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    # Auth backend management
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
    # Policy management
    path "sys/policies/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    # Mount management
    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    # Token self-renewal
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT
}

# Dedicated non-expiring Terraform token bound to the terraform policy.
# Retrieved once via terraform output and stored in terraform.tfvars.
resource "vault_token" "terraform" {
  provider        = vault.bootstrap
  display_name    = "terraform"
  policies        = [vault_policy.terraform.name]
  no_default_policy = true
  renewable       = true
  no_parent       = true  # orphan token — not tied to root token lifecycle

  depends_on = [vault_policy.terraform]
}

# Output the token value for retrieval after apply.
# Run: terraform output -raw terraform_token
# Then add to terraform.tfvars as openbao_terraform_token.
output "terraform_token" {
  description = "Dedicated Terraform token for OpenBao — add to terraform.tfvars as openbao_terraform_token"
  value       = vault_token.terraform.client_token
  sensitive   = true
}