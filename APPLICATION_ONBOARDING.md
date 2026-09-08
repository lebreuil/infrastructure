# Application Onboarding Guide

This guide is for application owners who want to deploy their applications
on the shared Kubernetes infrastructure.

**Developers do not have direct access to the cluster.** All interactions
with your application happen through:

- **GitHub** — for application manifests and Helm chart values
- **Argo CD UI** — for deployment status, sync and troubleshooting
- **OpenBao UI** — for secret management

Platform operators should use the [Secrets Management guide](SECRETS_MANAGEMENT.md)
to bootstrap OpenBao, create an application token, and initialise application
secrets with `app-secrets-init.py`. Application owners use this guide to store
and consume the secrets assigned to their application; they do not need the
Terraform or OpenBao bootstrap tokens.

---

## Architecture Overview

```
Cloudflare (DNS + Proxy + WAF)
    ↓
Infomaniak Floating IP
    ↓
Octavia Load Balancer (auto-provisioned)
    ↓
NGINX Ingress Controller
    ↓ TLS termination (cert-manager + Let's Encrypt)
    ├── your-app.your-domain.com → your application
    └── other-app.your-domain.com → other application

Secret management:
    OpenBao → External Secrets Operator → namespace-local Kubernetes Secret
    (the SecretStore and ExternalSecret are namespace-scoped)
```

All applications are deployed via **Argo CD** from GitHub repositories.

---

## Prepare the Infrastructure

Before onboarding an application, the platform team adds its Kubernetes
namespace, OpenBao namespace, policies, Kubernetes auth role, DNS record, and
ingress configuration to Terraform. See the [Secrets Management guide](SECRETS_MANAGEMENT.md)
for the OpenBao token and secret-initialisation workflow.

## Constraints and Requirements

### Cluster Layout

The cluster has two node pools with dedicated roles:

| Node Pool | Label | Purpose |
|---|---|---|
| Management | `custom.kaas.infomaniak.cloud/node-role: management` | NGINX, Argo CD, cert-manager, OpenBao |
| Worker | `custom.kaas.infomaniak.cloud/node-role: worker` | Application workloads |

**Your application pods must run on worker nodes.** See the
[Node Scheduling](#node-scheduling) section for how to configure this.

---

### Namespace

Each application must have its own dedicated namespace. You have two options:

**Option A — Let Argo CD create it** (simplest)

Set `CreateNamespace=true` in your sync options:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

**Option B — Define it explicitly in Git** (recommended if you need labels or annotations)

Create a `namespace.yaml` in your repository:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: your-app
  labels:
```

And set `CreateNamespace=false` in your sync options to prevent Argo CD
from overwriting it:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=false
```

---

### Secrets

**Never commit plain secrets to GitHub.** Secrets are managed in OpenBao and
synchronized by External Secrets Operator into a Kubernetes Secret in the
application namespace. The Secret is namespace-scoped and should only be
consumed by workloads in that namespace.

```
OpenBao (secret store)
    → namespace-local SecretStore (Kubernetes auth)
        → one shared External Secrets Operator controller
            (namespace permissions are granted only for registered applications)
            → ExternalSecret
                → Kubernetes Secret in your namespace
```

OpenBao namespace architecture:

```text
root namespace (Terraform token — namespace management only)
    ├── platform/          # Argo CD credentials, platform secrets
    │   ├── KV engine      (secret/)
    │   ├── k8s auth       (argocd-secret-sync service account)
    │   └── policy         (argocd — read secret/argocd-github-app)
    └── your-app/          # application team
        ├── KV engine      (secret/)
        ├── k8s auth       (ESO sync service account)
        ├── policy         (your-app-read — ESO SecretStore)
        └── policy         (your-app-write — application token)
```

#### Step 1 — Configure OpenBao for the application

Provide the platform team with:

- Your application name (used for the Kubernetes and OpenBao namespace)
- The application namespace (the platform team creates a dedicated ESO sync
  service account; application pod service accounts are not granted OpenBao
  access)


The platform team then:

- Creates an OpenBao namespace named `your-app`
- Enables a KV v2 mount named `secret`
- Creates read and write policies for the application team
- Creates the dedicated sync service account, its narrowly scoped ESO token
  permission, and the Kubernetes auth role binding it to the read policy
- Provides access to the OpenBao UI, when the application team is responsible
  for entering values

#### Step 2 — Store your secrets via the OpenBao UI

Access the OpenBao UI at `https://openbao.your-domain.com` using the
credentials for your application:

1. Select the `your-app` OpenBao namespace.
2. Navigate to **Secrets → secret → config**.
3. Click **Create new version**.
4. Add the required key-value pairs (for example, `postgresql-password` and
   `secret-key`).
5. Click **Save**.

The equivalent KV v2 API path is `secret/data/config`. If the platform team
initialises generated application secrets with `app-secrets-init.py`, update
the existing `config` secret in the UI instead of creating a second secret.

#### Step 3 — Declare the ESO resources in your application manifests

The application team owns the namespace-local `SecretStore` and
`ExternalSecret`. Commit them to the application repository so Argo CD
reconciles them with the rest of the application. The platform team creates
and provides the fixed sync service account name and OpenBao auth role; do not
use a `ClusterSecretStore` or a service account from another namespace.

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: openbao
  namespace: your-app
spec:
  provider:
    vault:
      server: https://openbao.your-domain.com
      path: secret
      version: v2
      namespace: your-app
      auth:
        kubernetes:
          mountPath: kubernetes
          role: your-app-secret-sync
          serviceAccountRef:
            name: your-app-secret-sync
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: your-app-secrets
  namespace: your-app
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: openbao
    kind: SecretStore
  target:
    name: your-app-secrets
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: config
```

The `SecretStore` and `ExternalSecret` must use the same namespace as the
application. The OpenBao `namespace`, auth `role`, and service account name
must match the values supplied by the platform team.

#### Step 4 — Reference the synchronized Kubernetes Secret

The `ExternalSecret` synchronizes the OpenBao KV v2 secret at `secret/config`
to a Kubernetes Secret in the same namespace. Reference that Secret from your
Helm values:

```yaml
envFrom:
  - secretRef:
      name: your-app-secrets
```

The synchronized Secret is updated periodically by ESO. Applications that
require a specific key can use `secretKeyRef` instead of `envFrom`.

If OpenBao is sealed or unreachable, ESO reports the sync failure on the
`ExternalSecret` resource and retains the last successfully synchronized
Secret. Contact the platform team if the resource is not `Ready`.

---

### Node Scheduling

All application pods **must** include a `nodeSelector` to schedule on
worker nodes. Without it, pods may land on management nodes and compete
with infrastructure components.

Add to your Helm values:

```yaml
# Required for all application components
nodeSelector:
  custom.kaas.infomaniak.cloud/node-role: "worker"

# If your chart has subcharts (e.g. PostgreSQL, Redis/Valkey),
# apply the nodeSelector to each subchart as well:
postgresql:
  primary:
    nodeSelector:
      custom.kaas.infomaniak.cloud/node-role: "worker"

redis:
  master:
    nodeSelector:
      custom.kaas.infomaniak.cloud/node-role: "worker"
  replica:
    nodeSelector:
      custom.kaas.infomaniak.cloud/node-role: "worker"

valkey:
  primary:
    nodeSelector:
      custom.kaas.infomaniak.cloud/node-role: "worker"
  replica:
    nodeSelector:
      custom.kaas.infomaniak.cloud/node-role: "worker"
```

---

### Service Type

Always use `ClusterIP` for your application service. External access
is handled by the NGINX Ingress Controller — **never use `LoadBalancer`
or `NodePort`** as this would provision an additional Octavia Load
Balancer on Infomaniak, incurring extra cost and bypassing the shared
ingress.

```yaml
service:
  type: ClusterIP  # always ClusterIP
```

---

### Ingress

External access to your application is provided via an `Ingress` resource
using the shared NGINX Ingress Controller and cert-manager for TLS.

Create an `ingress.yaml` in your repository:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: your-app-ingress
  namespace: your-app
  annotations:
    # Automatically provisions and renews a Let's Encrypt certificate
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # Redirects HTTP to HTTPS
    nginx.org/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - your-app.your-domain.com
      secretName: your-app-tls   # cert-manager stores the cert here
  rules:
    - host: your-app.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: your-app   # must match your Service name
                port:
                  number: 80
```

**Important:**
- The hostname must be a subdomain of `your-domain.com`
- The DNS record is managed via a wildcard
  `*.your-domain.com` — no DNS change is needed for new subdomains
- TLS certificates are issued automatically by cert-manager
- Do not set `service.type: LoadBalancer` — use `ClusterIP` + `Ingress`

---

### Replica Management

Avoid deploying unnecessary replicas for non-critical subcharts to
preserve cluster resources. For example, if your chart includes Redis
or Valkey and high availability is not required:

```yaml
valkey:
  architecture: standalone   # single instance, no replicas

redis:
  architecture: standalone
```

---

### Liveness and Readiness Probes

If your application requires time to start (e.g. database migrations),
increase the probe initial delay to avoid premature restarts:

```yaml
livenessProbe:
  initialDelaySeconds: 120   # allow 2 minutes for startup
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 5

readinessProbe:
  initialDelaySeconds: 60
  periodSeconds: 20
  timeoutSeconds: 10
  failureThreshold: 5
```

---

### Persistence

Persistent volumes use the OpenStack Cinder CSI driver. If your
application requires persistent storage:

```yaml
persistence:
  enabled: true
  storageClass: ""    # uses the cluster default storage class
  size: 10Gi
  accessModes:
    - ReadWriteOnce   # only ReadWriteOnce is supported
```

**Note:** `ReadWriteMany` is **not supported** on this cluster. If your
chart requires `ReadWriteMany`, set `replicaCount: 1` to avoid
multi-node volume attachment issues.

---

## Declaring Your Application in Argo CD

Applications are declared via Argo CD Application manifests committed
to the GitOps repository.

### Application Manifest

Create an Application manifest in the GitOps repository:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: your-app
  namespace: argocd
  # Ensures the Application is deleted when removed from Git
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    # Your application GitHub repository
    repoURL: https://github.com/your-org/your-app-repo
    targetRevision: HEAD   # or a specific branch/tag
    path: deploy           # path to your manifests in the repo

    # If deploying a Helm chart directly from a registry:
    # repoURL: oci://ghcr.io/your-org/your-chart
    # chart: your-chart
    # targetRevision: "1.0.0"
    # helm:
    #   valueFiles:
    #     - values.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: your-app

  syncPolicy:
    automated:
      prune: true       # removes resources deleted from Git
      selfHeal: true    # reverts manual changes to match Git
    syncOptions:
      # Use CreateNamespace=true if namespace is not defined in Git
      # Use CreateNamespace=false if namespace.yaml is in your repository
      - CreateNamespace=true
```

### Repository Structure

A typical application repository structure:

```
your-app-repo/
├── deploy/
│   ├── namespace.yaml          # Namespace definition (optional)
│   ├── ingress.yaml            # NGINX Ingress resource
│   └── values.yaml             # Helm chart values (including Secret references)
└── Chart.yaml                  # if this repo IS the Helm chart
```

Or if using a third-party Helm chart with your own values:

```
your-app-repo/
└── deploy/
    ├── namespace.yaml          # optional
    ├── ingress.yaml
    └── helm/
        ├── Chart.yaml          # references the upstream chart as dependency
        └── values.yaml         # your custom values including Secret references
```

The application team owns the namespace-local `SecretStore` and
`ExternalSecret`. The platform team owns the controller and the per-namespace
RBAC that lets it read and write only registered application namespaces.
Application repositories must not define a `ClusterSecretStore` or
cross-namespace secret reference.

---

## Monitoring Your Application via Argo CD UI

Since developers do not have direct cluster access, the **Argo CD UI**
is the primary tool for monitoring and troubleshooting deployments.

Access the Argo CD UI at `https://argocd.your-domain.com` using the
credentials provided by the platform team.

### Checking Application Status

The Argo CD UI shows the full state of your application:

| Status | Meaning |
|---|---|
| `Synced` | All resources match what is in Git |
| `OutOfSync` | Resources differ from Git — a sync is needed |
| `Healthy` | All pods are running and passing health checks |
| `Degraded` | One or more resources are unhealthy |
| `Progressing` | Resources are being created or updated |
| `Missing` | A resource defined in Git does not exist in the cluster |

### Checking Pod Status

In the Argo CD UI, click on your application then click on a **Pod**
resource to see:

- **Current status** (Running, Pending, CrashLoopBackOff etc.)
- **Events** — shows scheduling errors, image pull failures, probe failures
- **Logs** — shows stdout/stderr output from your container

### Checking Logs

Click on a **Pod** → **Logs** tab in the Argo CD UI to see:

- Container logs from your application
- Init container logs (useful for secret injection failures)
- Previous container logs (useful after a crash)

Select the container from the dropdown if your pod has multiple containers.

### Triggering a Manual Sync

If your application is `OutOfSync` or you want to force a redeployment:

1. Open your application in the Argo CD UI
2. Click **Sync**
3. Select the resources to sync (or leave all selected)
4. Click **Synchronize**

### Restarting a Pod

Since developers cannot use `kubectl`, pod restarts are done via Git:

1. Make a trivial change to your `values.yaml` (e.g. add an annotation)
2. Commit and push to GitHub
3. Argo CD will detect the change and redeploy the pod automatically

Or ask the platform team to restart the pod on your behalf.

---

## GitHub Actions Integration

To trigger Argo CD sync automatically on push to your main branch:

```yaml
# .github/workflows/deploy.yaml
name: Deploy

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Argo CD sync
        run: |
          argocd app sync your-app \
            --server argocd.your-domain.com \
            --auth-token ${{ secrets.ARGOCD_TOKEN }} \
            --grpc-web
```

Use an Argo CD authentication token with
the appropriate permissions for your application. Store it as a
GitHub Actions secret named `ARGOCD_TOKEN`.

---

## Checklist

Before submitting your application for deployment, verify:

- [ ] Namespace strategy chosen — `CreateNamespace=true` or explicit `namespace.yaml`
- [ ] No plain secrets committed to GitHub
- [ ] OpenBao access and the ESO sync service account provided by the platform team
- [ ] Secrets stored in the `your-app` OpenBao namespace at `secret/config`
  (via the OpenBao UI or the platform-managed initialisation workflow in the
  [Secrets Management guide](SECRETS_MANAGEMENT.md))
- [ ] Application references the synchronized `<app>-secrets` Kubernetes Secret
- [ ] `nodeSelector: custom.kaas.infomaniak.cloud/node-role: worker` set on all pods
- [ ] `service.type: ClusterIP` (never `LoadBalancer` or `NodePort`)
- [ ] `Ingress` resource defined with `ingressClassName: nginx`
- [ ] `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation on Ingress
- [ ] Hostname is a subdomain of `your-domain.com`
- [ ] Subcharts have `nodeSelector` applied
- [ ] Unnecessary replicas disabled for non-HA subcharts
- [ ] Liveness/readiness probe timeouts appropriate for startup time
- [ ] Argo CD Application manifest submitted to GitOps repository

---

## Getting Help

Developers do not have `kubectl` access. Use the following to
troubleshoot or escalate:

| Issue | What to do |
|---|---|
| Application not syncing | Check the **Sync** status in Argo CD UI → look at **Events** tab |
| Pod not starting | Check pod **Events** and **Logs** in Argo CD UI |
| Pod in `CrashLoopBackOff` | Check **Logs → Previous** in Argo CD UI |
| Secret synchronization failing | Ask the platform team to inspect the `ExternalSecret` status and events |
| Secrets not refreshing | Ask the platform team to inspect ESO controller logs and the `ExternalSecret` refresh time |
| Certificate not issuing | Check the `certificate` resource status in Argo CD UI |
| Pod not scheduling | Check pod **Events** in Argo CD UI for node affinity errors |
| OpenBao sealed or unreachable | Contact platform team |
| Infrastructure issues (nodes, networking) | Contact platform team |
| OpenBao access, policies and auth roles | Contact platform team |
| Argo CD access and GitOps repository | Contact platform team |
| Need a pod restarted | Contact platform team or push a trivial Git change |
