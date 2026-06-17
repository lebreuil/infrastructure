# Kubernetes Infrastructure on Infomaniak — Terraform

This repository contains the Terraform configuration to deploy and configure a production-ready Kubernetes infrastructure on [Infomaniak's managed Kubernetes service](https://www.infomaniak.com/en/hosting/public-cloud/kubernetes).

## Overview

The stack provisions and configures the following:

- **Worker nodes** on Infomaniak Public Cloud (OpenStack)
- **Cilium Gateway API** for external traffic routing
- **cert-manager** for automated TLS certificate management via Let's Encrypt
- **Argo CD** as the GitOps continuous delivery platform
- **Cloudflare** for DNS, proxying, and DDoS protection

## Architecture

```
Let's Encrypt
    ↕ DNS-01 challenge (cert-manager via Cloudflare API)

Cloudflare DNS + Proxy (Full Strict SSL)
    ↓
Infomaniak Floating IP
    ↓
Octavia Load Balancer (auto-provisioned by OpenStack CCM)
    ↓
Cilium Shared Gateway (TLS termination, wildcard cert *.your-domain.com)
    ↓
HTTPRoute → Argo CD (ClusterIP :80)
```

A single shared Cilium Gateway is used for all services to avoid
provisioning multiple Octavia Load Balancers and Floating IPs on
Infomaniak (one billable resource per LoadBalancer service).

## Prerequisites

- Terraform >= 1.5.0
- An Infomaniak Public Cloud account with a managed Kubernetes cluster already provisioned
- Gateway API CRDs installed in the cluster
- A Cloudflare account managing your domain's DNS
- A Cloudflare API token with the following permissions:
  - `Zone / DNS / Edit` — for cert-manager DNS-01 challenge
  - `Zone / Zone / Read` — for zone settings management

## Repository Structure

```
.
├── README.md
├── kaas.tf                    # Infomaniak worker node pool
├── gateway-api.tf             # Cilium Gateway API configuration and shared Gateway
├── cert-manager.tf            # cert-manager, Let's Encrypt issuer and wildcard certificate
├── argocd.tf                  # Argo CD Helm release, HTTPRoute and Cloudflare DNS records
├── variables.tf               # Input variable definitions
├── argocd-values.yaml         # Argo CD Helm chart values
└── cert-manager-values.yaml   # cert-manager Helm chart values
```

## Resources

### `kaas.tf` — Infomaniak worker nodes

| Resource | Type | Purpose |
|---|---|---|
| `workers` | `infomaniak_kaas_instance_pool` | Worker node pool for scheduling pods |

### `gateway-api.tf` — Cilium Gateway API

| Resource | Type | Purpose |
|---|---|---|
| `cilium_gateway_api` | `kubernetes_config_map_v1_data` | Enables Gateway API support in Cilium |
| `shared_gateway` | `kubernetes_manifest` | Single shared Cilium Gateway for all services |

### `cert-manager.tf` — TLS certificate management

| Resource | Type | Purpose |
|---|---|---|
| `cert_manager` | `helm_release` | Deploys cert-manager for TLS automation |
| `cloudflare_api_token` | `kubernetes_secret` | Stores Cloudflare credentials for cert-manager |
| `letsencrypt_issuer` | `kubernetes_manifest` | Configures Let's Encrypt ACME via DNS-01 |
| `wildcard_certificate` | `kubernetes_manifest` | Issues `*.your-domain.com` wildcard certificate |

### `argocd.tf` — Argo CD

| Resource | Type | Purpose |
|---|---|---|
| `argocd` | `helm_release` | Deploys Argo CD in the `argocd` namespace |
| `argocd_httproute` | `kubernetes_manifest` | Routes external traffic to Argo CD |
| `argocd` (DNS) | `cloudflare_record` | DNS A record pointing to the Floating IP |
| `ssl_strict` | `cloudflare_zone_settings_override` | Enforces Full Strict SSL on the Cloudflare zone |

## Providers

| Provider | Version | Purpose |
|---|---|---|
| `Infomaniak/infomaniak` | `~> 1.4` | Manages Infomaniak Kubernetes node pools |
| `hashicorp/helm` | `>= 2.9.0` | Deploys Helm charts (Argo CD, cert-manager) |
| `hashicorp/kubernetes` | `>= 2.0.0` | Manages Kubernetes resources |
| `cloudflare/cloudflare` | `~> 4.0` | Manages DNS records and zone settings |

## Variables

| Variable | Description | Sensitive |
|---|---|---|
| `kaas_id` | ID of the Infomaniak managed Kubernetes cluster | No |
| `infomaniak_token` | Infomaniak API token | Yes |
| `domain` | Base domain for all services (e.g. `your-domain.com`) | No |
| `letsencrypt_email` | Email for Let's Encrypt expiry notifications | No |
| `cloudflare_api_token` | Cloudflare API token for DNS and cert-manager | Yes |
| `cloudflare_zone_id` | Cloudflare Zone ID for your domain | No |

## Usage

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

2. **Review the plan:**
   ```bash
   terraform plan
   ```

3. **Apply the configuration:**
   ```bash
   terraform apply
   ```

4. **Retrieve the Argo CD initial admin password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath="{.data.password}" | base64 -d
   ```

5. **Access Argo CD** at `https://argocd.your-domain.com`

## Key Design Decisions

### Cilium Gateway API over direct LoadBalancer services
Services are exposed via a single shared Cilium Gateway rather than
individual `LoadBalancer` type services. This avoids provisioning one
Octavia Load Balancer and Floating IP per service on Infomaniak.

### Cilium Helm release not managed by Terraform
Cilium is installed and managed by Infomaniak as a cluster addon. To
avoid conflicts with Infomaniak's Helm release ownership, only the
`cilium-config` ConfigMap is patched to enable Gateway API.

### DNS-01 ACME challenge
Let's Encrypt certificates are issued via DNS-01 rather than HTTP-01
because DNS-01 supports wildcard certificates and works before the
Gateway has an external IP assigned.

### Cloudflare proxy enabled (Full Strict SSL)
Cloudflare proxies all traffic, providing DDoS protection and WAF.
Full Strict SSL mode ensures end-to-end encryption between Cloudflare
and the Cilium Gateway. The DNS-01 challenge is unaffected since
cert-manager only interacts with DNS TXT records, not proxied traffic.

## Netbox

A few things to note:

The netbox-values.yaml uses templatefile() in Terraform so domain and netbox_admin_email are injected at apply time without hardcoding them
The namespace is created by Terraform (not Argo CD) so the netbox-secrets Secret exists before Argo CD tries to deploy NetBox
The chart is pulled from the OCI registry (ghcr.io/netbox-community/netbox-chart) as per the official quickstart
You'll need to generate a netbox_secret_key — you can do that with openssl rand -base64 50
