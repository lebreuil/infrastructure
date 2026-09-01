# Root namespace — namespace management only
# All other resources live in child namespaces

path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/namespaces" {
  capabilities = ["read", "list"]
}

# Token management — required by Vault provider internals
path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/create/*" {
  capabilities = ["create", "update"]
}

path "auth/token/lookup" {
  capabilities = ["create", "update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Child namespaces — full management
path "+/sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "+/sys/mounts" {
  capabilities = ["read", "list"]
}

path "+/sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "+/sys/auth" {
  capabilities = ["read", "list"]
}

path "+/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "+/sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "+/sys/policies/acl" {
  capabilities = ["read", "list"]
}

path "+/secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "+/auth/token/create" {
  capabilities = ["create", "update"]
}

path "+/auth/token/lookup-self" {
  capabilities = ["read"]
}

path "+/auth/token/renew-self" {
  capabilities = ["update"]
}

path "+/auth/token/revoke-self" {
  capabilities = ["update"]
}
