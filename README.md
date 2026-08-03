# Kubernetes Infrastructure on Infomaniak — Terraform

This repository contains the Terraform configuration to deploy and configure
a production-ready Kubernetes infrastructure on
[Infomaniak's managed Kubernetes service](https://www.infomaniak.com/en/hosting/public-cloud/kubernetes).

---

## Overview

The platform stack provisions and configures the following infrastructure:

- **Kubernetes cluster** on Infomaniak Public Cloud with dedicated management and worker node pools
- **NGINX Ingress Controller** for external traffic routing (F5 maintained)
- **cert-manager** for automated TLS certificate management via Let's Encrypt
- **Argo CD** as the GitOps continuous delivery platform
- **OpenBao** as the secret management platform
- **Cloudflare** for DNS, proxying, and DDoS protection

Applications are deployed by their respective teams via Argo CD from
GitHub repositories. The platform team manages shared infrastructure only.

---

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
NGINX Ingress Controller (management nodes)
    ↓ TLS termination (per-service certs via cert-manager annotations)
    ├── argocd.your-domain.com  → Argo CD
    ├── openbao.your-domain.com → OpenBao
    └── *.your-domain.com       → Application workloads (worker nodes)

Secret management:
    OpenBao → Agent Injector sidecar → secrets as files in /bao/secrets/
    (secrets are NEVER stored as Kubernetes Secrets)

GitHub access:
    GitHub App (organisation-wide) → Argo CD credential template
    → all repositories under the organisation accessible automatically
```

---

## Repository Structure

```
platform/
├── terraform/
│   ├── README.md
│   ├── TROUBLESHOOTING.md
│   ├── main.tf                    # Provider configurations
│   ├── variables.tf               # Input variable definitions
│   ├── terraform.tfvars           # Variable values (not committed)
│   ├── kaas.tf                    # Cluster and node pools
│   ├── dns.tf                     # Wildcard Cloudflare DNS record
│   ├── network.tf                 # OpenStack subnet lookup
│   ├── ingress-controller.tf      # NGINX Ingress Controller
│   ├── cert-manager.tf            # cert-manager + ClusterIssuer
│   ├── argocd.tf                  # Argo CD bootstrap
│   ├── openbao.tf                 # OpenBao deployment
│   ├── openbao-config.tf          # OpenBao auth + per-app policies
│   ├── nginx-values.yaml          # NGINX Helm values
│   ├── cert-manager-values.yaml   # cert-manager Helm values
│   ├── argocd-values.yaml         # Argo CD Helm values (GitHub App config)
│   └── openbao-values.yaml        # OpenBao Helm values
└── gitops/
    └── applications/
        └── netbox-application.yaml  # Argo CD Application manifest
```

Application repositories follow this structure (managed by app teams):

```
netbox-repo/
└── deploy/
    ├── namespace.yaml             # Namespace definition
    ├── serviceaccount.yaml        # Service account (bound to OpenBao role)
    ├── ingress.yaml               # NGINX Ingress resource
    └── values.yaml                # Helm chart values + OpenBao annotations
```

---

## Resources

### `kaas.tf` — Cluster and node pools

| Resource | Type | Purpose |
|---|---|---|
| `cluster` | `infomaniak_kaas` | Managed Kubernetes cluster |
| `management` | `infomaniak_kaas_instance_pool` | Management node pool (NGINX, Argo CD, cert-manager, OpenBao) |
| `workers` | `infomaniak_kaas_instance_pool` | Worker node pool (application workloads) |

### `network.tf` — OpenStack networking

| Resource | Type | Purpose |
|---|---|---|
| `workers` | `kubernetes_nodes` | Reads worker node provider IDs |
| `worker` | `openstack_networking_port_v2` | Reads worker node port |
| `current` | `openstack_identity_auth_scope_v3` | Reads OpenStack project ID |
| `kaas` | `openstack_networking_subnet_v2` | Looks up cluster subnet ID |

### `ingress-controller.tf` — NGINX Ingress Controller

| Resource | Type | Purpose |
|---|---|---|
| `nginx_ingress` | `helm_release` | Deploys F5 NGINX Ingress Controller |
| `nginx_ingress` | `kubernetes_service_v1` | Reads LoadBalancer IP for DNS records |

### `cert-manager.tf` — TLS certificate management

| Resource | Type | Purpose |
|---|---|---|
| `cert_manager` | `helm_release` | Deploys cert-manager |
| `cloudflare_api_token` | `kubernetes_secret` | Stores Cloudflare API token for DNS-01 |
| `letsencrypt_issuer` | `kubectl_manifest` | Configures Let's Encrypt ClusterIssuer |

### `dns.tf` — Cloudflare DNS

| Resource | Type | Purpose |
|---|---|---|
| `apex` | `cloudflare_record` | Apex `your-domain.com` → NGINX IP |
| `ssl_strict` | `cloudflare_zone_settings_override` | Enforces Full Strict SSL |

Note: per-application DNS records are not managed here. They are
created in `openbao-config.tf` as part of each application onboarding.

### `argocd.tf` — Argo CD

| Resource | Type | Purpose |
|---|---|---|
| `argocd` | `helm_release` | Deploys Argo CD with GitHub App config |
| `argocd` | `cloudflare_record` | `argocd.your-domain.com` → NGINX IP |

### `openbao.tf` — OpenBao

| Resource | Type | Purpose |
|---|---|---|
| `openbao` | `helm_release` | Deploys OpenBao with Agent Injector |
| `openbao` | `cloudflare_record` | `openbao.your-domain.com` → NGINX IP |

### `openbao-config.tf` — OpenBao configuration + per-application onboarding

This file contains both platform-level OpenBao configuration and
per-application onboarding resources. Adding a new application requires
adding three resources to this file — a policy, a Kubernetes auth role,
and a Cloudflare DNS record.

**Platform resources (created once):**

| Resource | Type | Purpose |
|---|---|---|
| `kv` | `vault_mount` | Enables KV v2 secrets engine |
| `kubernetes` | `vault_auth_backend` | Enables Kubernetes auth |
| `kubernetes` | `vault_kubernetes_auth_backend_config` | Configures Kubernetes auth |
| `argocd` | `vault_policy` | Policy for Argo CD repo server |
| `argocd` | `vault_kubernetes_auth_backend_role` | Role for Argo CD repo server |

**Per-application resources (one set per application):**

| Resource | Type | Purpose |
|---|---|---|
| `netbox` | `vault_policy` | Read-only policy for NetBox secrets |
| `netbox` | `vault_kubernetes_auth_backend_role` | Role for NetBox agent injector |
| `netbox` | `cloudflare_record` | `netbox.your-domain.com` → NGINX IP |

### `gitops/applications/netbox-application.yaml` — NetBox Argo CD Application

| Field | Value |
|---|---|
| Source | `https://github.com/your-org/netbox-repo` |
| Path | `deploy/` |
| Destination | `netbox` namespace |
| Sync | Automated with prune and selfHeal |

---

## Providers

| Provider | Version | Purpose |
|---|---|---|
| `Infomaniak/infomaniak` | `~> 1.4` | Manages Infomaniak KaaS cluster and node pools |
| `hashicorp/helm` | `>= 2.9.0` | Deploys Helm charts |
| `hashicorp/kubernetes` | `>= 2.0.0` | Manages Kubernetes resources |
| `gavinbunney/kubectl` | `~> 1.14` | Applies manifests without CRD validation |
| `cloudflare/cloudflare` | `~> 4.0` | Manages DNS records and zone settings |
| `terraform-provider-openstack/openstack` | `~> 2.0` | Looks up OpenStack networking resources |
| `hashicorp/vault` | `~> 4.0` | Configures OpenBao (API-compatible with Vault) |

---

## Variables

### Infrastructure

| Variable | Description | Sensitive |
|---|---|---|
| `public_cloud_id` | Infomaniak Public Cloud ID | No |
| `public_cloud_project_id` | Infomaniak Public Cloud project ID | No |
| `domain` | Base domain (e.g. `your-domain.com`) | No |
| `os_cloud` | OpenStack cloud name from `clouds.yaml` | No |

### Cloudflare

| Variable | Description | Sensitive |
|---|---|---|
| `cloudflare_api_token` | Cloudflare API token | Yes |
| `cloudflare_zone_id` | Cloudflare Zone ID | No |

### cert-manager

| Variable | Description | Sensitive |
|---|---|---|
| `letsencrypt_email` | Email for Let's Encrypt expiry notifications | No |

### OpenBao

| Variable | Description | Sensitive |
|---|---|---|
| `openbao_root_token` | OpenBao root token (generated at init) | Yes |

---

## Usage

### Deployment order

The first deployment must follow a strict phase order due to resource
dependencies. Terraform resolves dependencies automatically on subsequent
runs — the phased approach is only required on the very first deployment
or after a full cluster recreation.

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1 — Cluster                                              │
│  infomaniak_kaas.cluster                                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Phase 2 — Node pools (parallel)                                │
│  instance_pool.management        instance_pool.workers          │
└──────────────┬────────────────────────────┬─────────────────────┘
               │                            │
┌──────────────▼────────────────────────────▼─────────────────────┐
│  Phase 3 — Network + shared infrastructure (parallel)           │
│  network.tf          helm_release.nginx     helm_release.        │
│  (subnet lookup)     (NGINX Ingress)        cert_manager         │
└──────────────┬────────────────┬────────────────────┬────────────┘
               │                │                    │
┌──────────────▼────────────────▼────────────────────▼────────────┐
│  Phase 4 — DNS + issuers + Argo CD (parallel)                   │
│  cloudflare_record.*    kubectl_manifest.    helm_release.       │
│  (wildcard DNS)         letsencrypt_issuer   argocd              │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│  Phase 5 — OpenBao                                              │
│  helm_release.openbao                                           │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│  Phase 6 — Manual steps + OpenBao config                        │
│  bao operator init     bao operator unseal    openbao-config.tf │
│  (save keys + token)   (3 of 5 keys)          (terraform apply) │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│  Phase 7 — Secrets + applications                               │
│  OpenBao UI (manual secrets)   Argo CD syncs apps automatically │
└─────────────────────────────────────────────────────────────────┘
```

---

### Phase 1 — Cluster

```bash
terraform init
terraform apply -target=infomaniak_kaas.cluster
```

Everything depends on the cluster existing first.

---

### Phase 2 — Node pools

Only the management nodes are required at this stage.

```bash
terraform apply -target=infomaniak_kaas_instance_pool.management
```

Both pools depend on the cluster. `network.tf` depends on worker nodes
having running pods with a `providerID` — so workers must exist before
Phase 3.

---

### Phase 3 — Network + shared infrastructure

```bash
# Subnet lookup (depends on management nodes)
terraform apply -target=data.openstack_networking_port_v2.worker
terraform apply -target=data.openstack_networking_subnet_v2.kaas

# NGINX and cert-manager can run in parallel
terraform apply -target=helm_release.nginx_ingress
terraform apply -target=helm_release.cert_manager
```

NGINX needs the subnet ID from `network.tf` to configure the Octavia
Load Balancer annotation.  
cert-manager is independent of the subnet.

---

### Phase 4 —  issuers + Argo CD

```bash
# Requires cert-manager
terraform apply -target=kubectl_manifest.letsencrypt_issuer

# Requires management nodes
terraform apply -target=helm_release.argocd
terraform apply -target=kubernetes_ingress_v1.argocd
terraform apply -target=cloudflare_dns_record.argocd
terraform apply -target=kubectl_manifest.app_of_apps
```

---

### Phase 5 — OpenBao installation

```bash
# Requires NGINX (ingress) and cert-manager (TLS)
terraform apply -target=helm_release.openbao
terraform apply -target=kubernetes_ingress_v1.openbao
terraform apply -target=cloudflare_dns_record.openbao

```

---

### Phase 6 — Manual steps + OpenBao configuration

OpenBao must be initialized and unsealed before the Vault Terraform
provider can connect to configure it.

#### Initialize openbao

```bash
# Step 1 — Initialize OpenBao (one-time only)
kubectl exec -n openbao openbao-0 -- bao operator init

# Step 2 — Save the 5 unseal keys and root token securely
# These CANNOT be recovered if lost — store in a password manager

# Step 3 — Unseal OpenBao (requires 3 of 5 keys)
kubectl exec -n openbao openbao-0 -- bao operator unseal <key-1>
kubectl exec -n openbao openbao-0 -- bao operator unseal <key-2>
kubectl exec -n openbao openbao-0 -- bao operator unseal <key-3>

# Step 4 — Verify OpenBao is unsealed
kubectl exec -n openbao openbao-0 -- bao status

```

#### Create the Terraform policy

```bash
kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=<root-token> \
  bao policy write terraform - << 'EOF'

# KV secrets engine management
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Auth backend management
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Policy management
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Secrets engine mount management
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Auth mount listing — needed by Vault provider initialization
path "sys/auth" {
  capabilities = ["read", "list"]
}

# Token self-management
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
```

#### verify that the policy eas created

```bash
kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=<root-token> \
  bao policy read terraform
```

#### Create the dedicated Terraform token

```bash
TOKEN=$(kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=<root-token> \
  bao token create \
    -policy=terraform \
    -display-name=terraform \
    -no-default-policy \
    -orphan \
    -ttl=0 \
    -field=token)

echo "Token: $TOKEN"
```

#### Add the token to terraform.tfvars

```bash
echo "openbao_terraform_token = \"$TOKEN\"" >> terraform.tfvars
```

#### Verify the token has the correct permissions

```bash
kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=$TOKEN \
  bao token lookup -self
```

#### Revoke the root token

Only after verifying the Terraform token works correctly:

```bash
# Run terraform plan to confirm the token works
terraform plan

# If plan succeeds, revoke the root token
kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=<root-token> \
  bao token revoke -self

# Verify root token is revoked
kubectl exec -n openbao openbao-0 -- \
  env BAO_TOKEN=<root-token> \
  bao token lookup -self
# Should return: Code: 403. Errors: permission denied
```

---

### Phase 7 — Apply OpenBao configuration

```bash
terraform apply -target=vault_mount.kv
terraform apply -target=vault_auth_backend.kubernetes
terraform apply -target=vault_kubernetes_auth_backend_config.kubernetes
terraform apply  # applies remaining policies and roles
```

---

### Phase 8 — Secrets + applications

Create teh github App.  


```bash
# Step 1 — Store GitHub App credentials in OpenBao UI
# Path: secret/platform/argocd-github-app
# Keys: app-id, installation-id, private-key

# Step 2 — Restart Argo CD repo server to pick up GitHub App credentials
kubectl rollout restart deployment/argocd-repo-server -n argocd

# Step 3 — Platform team stores application secrets in OpenBao UI
# Path: secret/<app-name>/config

# Step 4 — Argo CD automatically syncs all registered applications
# No further action needed
```

Next steps will require the worker nodes to be deployed.

```bash
terraform apply -target=infomaniak_kaas_instance_pool.workers
```

---

### Subsequent applies

After the initial phased deployment, all subsequent applies are
straightforward:

```bash
terraform plan
terraform apply
```

Terraform resolves all dependencies automatically via `depends_on`.

---

### Cluster recreation

On full cluster recreation the phased approach must be repeated.
The only irreplaceable step is recovering the OpenBao unseal keys
from secure storage:

```
Phase 1-5  → terraform apply (fully automatic)
Phase 6    → unseal OpenBao with saved keys (manual)
           → terraform apply openbao-config.tf (automatic)
Phase 7    → recreate secrets in OpenBao UI (manual)
           → Argo CD syncs all applications (automatic)
```

| Step | Automated | Manual |
|---|---|---|
| Cluster + nodes + infra | ✅ | |
| NGINX, cert-manager, Argo CD, OpenBao | ✅ | |
| OpenBao unseal | | ✅ Requires saved unseal keys |
| OpenBao auth + policies | ✅ | |
| GitHub App credentials | | ✅ OpenBao UI |
| Application secrets | | ✅ OpenBao UI |
| Application deployments | ✅ Argo CD | |

---

### Onboarding a new application

1. Add three resources to `applications.tf` for the new application:
   - `vault_policy.<app>` — read-only access to `secret/data/<app>/*`
   - `vault_kubernetes_auth_backend_role.<app>` — binds service account to policy
   - `cloudflare_record.<app>` — DNS A record for `<app>.your-domain.com`

   Then apply:
   ```bash
   terraform apply
   ```

2. Application team creates secrets in OpenBao UI at `secret/<app>/config`

3. Add `gitops/applications/<app>-application.yaml` to register the app in Argo CD

4. Argo CD automatically syncs the application — DNS and TLS are already in place

---

## Key Design Decisions

### GitOps ownership split
The platform team owns infrastructure (Terraform) and application
registration (Argo CD Application manifests). Application teams own
their Helm chart values, ingress rules and namespace definitions.
This separation allows application teams to deploy independently
without platform team involvement after initial onboarding.

### Organisation-wide GitHub App credential template
A single GitHub App is installed at the organisation level. Argo CD
is configured with a credential template (`repo-creds`) covering
`https://github.com/your-org`, making all repositories under the
organisation automatically accessible without per-repository
configuration. New application repositories need no Argo CD credential
changes.

### OpenBao Agent Injector over Kubernetes Secrets
Secrets are never stored as Kubernetes Secrets. The OpenBao Agent
Injector injects a sidecar into application pods that fetches secrets
directly from OpenBao and writes them as files to an in-memory tmpfs
volume at `/bao/secrets/`. This means secrets exist only in OpenBao
and in pod memory — they are never persisted to etcd.

### Per-application DNS records
Each application gets its own Cloudflare DNS A record created as part
of the platform onboarding process in `openbao-config.tf`. This keeps
all per-application platform resources (policy, role, DNS) in one place,
making onboarding and offboarding explicit and auditable. Removing an
application means removing its three resources from `openbao-config.tf`
and running `terraform apply` — the DNS record, OpenBao access and
Argo CD application are all cleaned up in one operation.

### Two node pools with dedicated roles
Management nodes run platform infrastructure (NGINX, Argo CD,
cert-manager, OpenBao). Worker nodes run application workloads.
The `custom.kaas.infomaniak.cloud/node-role` label on each pool
allows precise pod scheduling via `nodeSelector` in Helm values.

### NGINX Ingress Controller over Cilium Gateway API
The initial design used Cilium Gateway API. This was abandoned due
to incompatibilities with Infomaniak's shared cluster — see the
section below for details.

### F5 NGINX over community ingress-nginx
The community ingress-nginx project reached end-of-life in March 2026.
The F5/NGINX Inc. maintained controller was chosen as its replacement.

### `kubectl_manifest` over `kubernetes_manifest`
The `gavinbunney/kubectl` provider skips CRD validation at plan time,
avoiding chicken-and-egg failures when CRDs are not yet installed.

### cert-manager with DNS-01 ACME challenge
DNS-01 works before the ingress controller has an IP, supports wildcard
certificates, and uses Cloudflare for DNS record management.

### Cloudflare Full Strict SSL
Cloudflare proxies all traffic for DDoS protection and WAF. Full Strict
SSL ensures end-to-end encryption between Cloudflare and NGINX using
Let's Encrypt certificates provisioned by cert-manager.

---

## Why Cilium Gateway API Was Not Used

The initial architecture used Cilium Gateway API. This failed due to:

### 1. Cilium operator crash
After enabling `enable-gateway-api: "true"` in `cilium-config`, the
Cilium operator crashed requiring `TLSRoute` in
`gateway.networking.k8s.io/v1alpha2` which the standard channel CRDs
mark as `served=false`.

### 2. CRD channel conflict
Switching to the experimental channel (which serves `v1alpha2`) is
blocked by a `ValidatingAdmissionPolicy` installed by the standard
channel:

```
Installing experimental CRDs on top of standard channel CRDs is
prohibited by default.
```

### 3. Shared cluster impact
Deleting the `ValidatingAdmissionPolicy` would affect all tenants on
the shared cluster. The Cilium operator restart also caused a temporary
network disruption for all tenants.

### 4. Lesson learned
On a shared managed cluster, cluster-level components should only be
modified by the platform provider. If Cilium Gateway API support is
needed, open a support ticket with Infomaniak.
