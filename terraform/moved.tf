moved {
  from = kubernetes_namespace_v1.netbox
  to   = module.application["netbox"].kubernetes_namespace_v1.application
}

moved {
  from = kubernetes_service_account_v1.netbox_secret_sync
  to   = module.application["netbox"].kubernetes_service_account_v1.secret_sync
}

moved {
  from = kubernetes_role_v1.netbox_secret_sync_token
  to   = module.application["netbox"].kubernetes_role_v1.secret_sync_token
}

moved {
  from = kubernetes_role_binding_v1.netbox_secret_sync_token
  to   = module.application["netbox"].kubernetes_role_binding_v1.secret_sync_token
}

moved {
  from = vault_namespace.netbox
  to   = module.application["netbox"].vault_namespace.application
}

moved {
  from = vault_mount.netbox_kv
  to   = module.application["netbox"].vault_mount.kv
}

moved {
  from = vault_auth_backend.netbox_kubernetes
  to   = module.application["netbox"].vault_auth_backend.kubernetes
}

moved {
  from = vault_kubernetes_auth_backend_config.netbox
  to   = module.application["netbox"].vault_kubernetes_auth_backend_config.application
}

moved {
  from = vault_policy.netbox_read
  to   = module.application["netbox"].vault_policy.read
}

moved {
  from = vault_policy.netbox_write
  to   = module.application["netbox"].vault_policy.write
}

moved {
  from = vault_kubernetes_auth_backend_role.netbox_secret_sync
  to   = module.application["netbox"].vault_kubernetes_auth_backend_role.secret_sync
}

moved {
  from = kubernetes_ingress_v1.netbox
  to   = module.application["netbox"].kubernetes_ingress_v1.application
}

moved {
  from = cloudflare_dns_record.netbox
  to   = module.application["netbox"].cloudflare_dns_record.application
}

moved {
  from = cloudflare_zero_trust_access_application.netbox
  to   = module.application["netbox"].cloudflare_zero_trust_access_application.application
}
