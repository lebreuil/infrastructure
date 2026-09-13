moved {
  from = kubernetes_ingress_v1.podinfo
  to   = module.application["podinfo"].kubernetes_ingress_v1.application
}

moved {
  from = cloudflare_dns_record.podinfo
  to   = module.application["podinfo"].cloudflare_dns_record.application
}

moved {
  from = cloudflare_zero_trust_access_application.podinfo
  to   = module.application["podinfo"].cloudflare_zero_trust_access_application.application
}
