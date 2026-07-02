# Kubernetes Infrastructure on Infomaniak — Terraform

This repository contains the Terraform configuration to deploy and configure a production-ready Kubernetes infrastructure on [Infomaniak's managed Kubernetes service](https://www.infomaniak.com/en/hosting/public-cloud/kubernetes).

## Overview

The stack provisions and configures the following:

- **A managed Kubernetes cluster** on Infomaniak public Cloud 
- **Worker nodes** on Infomaniak Public Cloud (OpenStack)
- **NGINX Ingress Controller** for external traffic routing
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
NGINX Ingress Controller (runs on dedicated worker nodes)
    ↓ TLS termination (per-service certs via cert-manager annotations)
    ├── Ingress → Argo CD   (argocd-server:80)
    └── Ingress → NetBox    (netbox:80)
```

A single NGINX Ingress Controller handles all external traffic, resulting
in a single Octavia Load Balancer and Floating IP on Infomaniak regardless
of how many services are exposed.

## Prerequisites

- Terraform >= 1.5.0
- An Infomaniak Public Cloud account already provisioned
- A Cloudflare account managing your domain's DNS
- A Cloudflare API token with the following permissions:
  - `Zone / DNS / Edit` — for cert-manager DNS-01 challenge
  - `Zone / Zone / Read` — for zone settings management

## Repository Structure

```
.
├── README.md
├── kaas.tf                    # Infomaniak worker node pool
├── ingress-controller.tf      # NGINX Ingress Controller and IP provisioning
├── cert-manager.tf            # cert-manager and Let's Encrypt ClusterIssuer
├── argocd.tf                  # Argo CD Helm release, Ingress and Cloudflare DNS record
├── variables.tf               # Input variable definitions
├── argocd-values.yaml         # Argo CD Helm chart values
├── cert-manager-values.yaml   # cert-manager Helm chart values
└── nginx-values.yaml          # NGINX Ingress Controller Helm chart values
```

## Resources

### `kaas.tf` — Infomaniak worker nodes

| Resource | Type | Purpose |
|---|---|---|
| `cluster` | `infomaniak_kaas` | Infomaniak kubernetes cluster |
| `management` | `infomaniak_kaas_instance_pool` | Worker node pool for scheduling management pods |
| `workers` | `infomaniak_kaas_instance_pool` | Worker node pool for scheduling application pods |

### `ingress-controller.tf` — NGINX Ingress Controller

| Resource | Type | Purpose |
|---|---|---|
| `nginx_ingress` | `helm_release` | Deploys NGINX Ingress Controller |

### `cert-manager.tf` — TLS certificate management

| Resource | Type | Purpose |
|---|---|---|
| `cert_manager` | `helm_release` | Deploys cert-manager for TLS automation |
| `cloudflare_api_token` | `kubernetes_secret` | Stores Cloudflare credentials for cert-manager |
| `letsencrypt_issuer` | `kubectl_manifest` | Configures Let's Encrypt ACME via DNS-01 |

### `argocd.tf` — Argo CD

| Resource | Type | Purpose |
|---|---|---|
| `argocd` | `helm_release` | Deploys Argo CD in the `argocd` namespace |
| `argocd_ingress` | `kubectl_manifest` | Ingress rule routing traffic to Argo CD |
| `argocd` (DNS) | `cloudflare_record` | DNS A record pointing to the Floating IP |


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
6. **Access NetBox** at `https://netbox.your-domain.com`

