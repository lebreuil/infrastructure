# Kubernetes Infrastructure on Infomaniak — Terraform

This repository contains the Terraform configuration to deploy and configure a production-ready Kubernetes infrastructure on [Infomaniak's managed Kubernetes service](https://www.infomaniak.com/en/hosting/public-cloud/kubernetes).

## Overview

The stack provisions and configures the following:

- **A managed Kubernetes cluster** on Infomaniak public Cloud 
- **Worker nodes** on Infomaniak Public Cloud (OpenStack)
- **NGINX Ingress Controller** for external traffic routing
- **cert-manager** for automated TLS certificate management via Let's Encrypt
- **Argo CD** as the GitOps continuous delivery platform
- **NetBox** as the network source of truth, deployed via Argo CD
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
├── netbox.tf                  # NetBox Argo CD Application, Ingress and Cloudflare DNS record
├── variables.tf               # Input variable definitions
├── argocd-values.yaml         # Argo CD Helm chart values
├── cert-manager-values.yaml   # cert-manager Helm chart values
└── nginx-values.yaml          # NGINX Ingress Controller Helm chart values
```

## Resources

### `kaas.tf` — Infomaniak worker nodes

| Resource | Type | Purpose |
|---|---|---|
| `workers` | `infomaniak_kaas_instance_pool` | Worker node pool for scheduling pods |

### `ingress-controller.tf` — NGINX Ingress Controller

| Resource | Type | Purpose |
|---|---|---|
| `nginx_ingress` | `helm_release` | Deploys NGINX Ingress Controller |
| `nginx_ingress_ip` | `terraform_data` | Waits for Floating IP assignment by OpenStack CCM |
| `nginx_ingress_ip` | `local_file` | Reads the assigned Floating IP for DNS records |

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

### `netbox.tf` — NetBox

| Resource | Type | Purpose |
|---|---|---|
| `netbox_namespace` | `kubernetes_manifest` | Creates the `netbox` namespace |
| `netbox_secrets` | `kubernetes_secret` | Stores NetBox sensitive credentials |
| `netbox` | `argocd_application` | Deploys NetBox via Argo CD |
| `netbox_ingress` | `kubectl_manifest` | Ingress rule routing traffic to NetBox |
| `netbox` (DNS) | `cloudflare_record` | DNS A record pointing to the Floating IP |

## Providers

| Provider | Version | Purpose |
|---|---|---|
| `Infomaniak/infomaniak` | `~> 1.4` | Manages Infomaniak Kubernetes node pools |
| `hashicorp/helm` | `>= 2.9.0` | Deploys Helm charts (Argo CD, cert-manager, NGINX) |
| `hashicorp/kubernetes` | `>= 2.0.0` | Manages Kubernetes resources |
| `gavinbunney/kubectl` | `~> 1.14` | Applies Kubernetes manifests without CRD validation |
| `cloudflare/cloudflare` | `~> 4.0` | Manages DNS records and zone settings |
| `oboukili/argocd` | `~> 6.0` | Manages Argo CD Applications |
| `hashicorp/local` | `~> 2.0` | Reads local files (ingress IP) |

## Variables

| Variable | Description | Sensitive |
|---|---|---|
| `kaas_id` | ID of the Infomaniak managed Kubernetes cluster | No |
| `infomaniak_token` | Infomaniak API token | Yes |
| `domain` | Base domain for all services (e.g. `your-domain.com`) | No |
| `letsencrypt_email` | Email for Let's Encrypt expiry notifications | No |
| `cloudflare_api_token` | Cloudflare API token for DNS and cert-manager | Yes |
| `cloudflare_zone_id` | Cloudflare Zone ID for your domain | No |
| `argocd_admin_password` | Argo CD admin password for Terraform provider auth | Yes |
| `netbox_secret_key` | Django secret key for NetBox (min 50 chars) | Yes |
| `netbox_superuser_password` | Initial NetBox admin password | Yes |
| `netbox_superuser_api_token` | Initial NetBox admin API token (40 hex chars) | Yes |
| `netbox_postgresql_password` | PostgreSQL password for NetBox | Yes |
| `netbox_redis_password` | Redis password for NetBox | Yes |
| `netbox_admin_email` | Email address for the NetBox admin superuser | No |

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

## Key Design Decisions

### NGINX Ingress Controller over Cilium Gateway API
The initial design used Cilium Gateway API for external traffic routing.
This approach was abandoned due to fundamental incompatibilities with
Infomaniak's shared Kubernetes cluster model. See the section below for
the full explanation.

NGINX Ingress Controller was chosen as the replacement because it runs
entirely on dedicated worker nodes with no cluster-level changes required,
ensuring complete tenant isolation.

### Single ingress controller for all services
All services are exposed through a single NGINX Ingress Controller,
resulting in a single Octavia Load Balancer and Floating IP on Infomaniak.
This avoids provisioning one billable load balancer resource per service.

### Cilium Helm release not managed by Terraform
Cilium is installed and managed by Infomaniak as a cluster addon. To
avoid conflicts with Infomaniak's Helm release ownership, Terraform does
not manage the Cilium Helm release.

### `kubectl_manifest` over `kubernetes_manifest`
The `gavinbunney/kubectl` provider's `kubectl_manifest` resource is used
instead of the Hashicorp `kubernetes_manifest` resource throughout. The
`kubernetes_manifest` resource validates all resources against the live
cluster API during plan, apply, and destroy — causing failures when CRDs
are not yet installed or have been removed. `kubectl_manifest` skips this
validation, behaving like `kubectl apply` and avoiding chicken-and-egg
dependency issues.

### cert-manager with DNS-01 ACME challenge
Let's Encrypt certificates are issued via DNS-01 rather than HTTP-01
because DNS-01 works before the ingress controller has an external IP
assigned, and supports potential future wildcard certificates. TLS
certificates are provisioned automatically per service via the
`cert-manager.io/cluster-issuer` annotation on each Ingress resource.

### Cloudflare proxy enabled (Full Strict SSL)
Cloudflare proxies all traffic, providing DDoS protection and WAF.
Full Strict SSL mode ensures end-to-end encryption between Cloudflare
and the NGINX Ingress Controller. The DNS-01 challenge is unaffected
since cert-manager only interacts with DNS TXT records, not proxied
traffic.

### NetBox deployed via Argo CD
NetBox is deployed as an Argo CD Application rather than a direct
`helm_release` resource. This means NetBox lifecycle (sync, rollback,
health) is managed by Argo CD and visible in the Argo CD web UI,
following GitOps principles.

## Why Cilium Gateway API Was Not Used

The initial architecture was designed around Cilium Gateway API, which
offered a modern, expressive routing model via `Gateway` and `HTTPRoute`
resources. However, this approach failed due to the following chain of
incompatibilities specific to Infomaniak's shared Kubernetes cluster:

### 1. Cilium 1.19.1 requires `TLSRoute`

Cilium 1.19.1 requires `TLSRoute` in `gateway.networking.k8s.io/v1alpha2`
to be served, but the installed Gateway API CRDs (v1.5.0 standard channel)
mark `v1alpha2` as `served=false`.

### 2. Standard vs experimental CRD channel conflict
The fix would have been to switch from the standard Gateway API CRD channel
to the experimental channel, which keeps `v1alpha2` served. However, the
standard channel installs a `ValidatingAdmissionPolicy` named
`safe-upgrades.gateway.networking.k8s.io` that explicitly blocks this
upgrade:

```
Installing experimental CRDs on top of standard channel CRDs is prohibited
by default. Uninstall ValidatingAdmissionPolicy
safe-upgrades.gateway.networking.k8s.io to install experimental CRDs
on top of standard channel CRDs.
```

### 3. Shared cluster tenant isolation conflict
Deleting the `ValidatingAdmissionPolicy` is not viable on a shared cluster
because:
- CRDs and `ValidatingAdmissionPolicies` are cluster-scoped resources
  shared across all tenants
- Removing the policy would affect all other tenants on the cluster
- Infomaniak may restore it automatically, causing Terraform drift
- The Cilium operator restart caused a temporary network disruption
  for all tenants

### 4. Lesson learned
On a shared managed Kubernetes cluster, cluster-level components
(CRDs, CNI configuration, admission policies) should only be modified
by the platform provider. Tenant workloads should be confined to
namespace-scoped resources running on dedicated worker nodes.

If Cilium Gateway API support is needed in the future, the correct
approach is to open a support ticket with Infomaniak and request that
they officially enable and support it on their platform.