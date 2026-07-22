# Application Onboarding Guide

This guide is for application owners who want to deploy their applications
on the shared Kubernetes infrastructure managed by the platform team.

**Developers do not have direct access to the cluster.** All interactions
with your application happen through:
- **GitHub** — for application manifests and Helm chart values
- **Argo CD UI** — for deployment status, sync and troubleshooting
- **OpenBao UI** — for secret management

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
    OpenBao → Agent Injector sidecar → secrets as files in /bao/secrets/
    (secrets are NEVER stored as Kubernetes Secrets)
```

All applications are deployed via **Argo CD** from GitHub repositories.

---

## Cluster Layout

The cluster has two node pools with dedicated roles:

| Node Pool | Label | Purpose |
|---|---|---|
| Management | `custom.kaas.infomaniak.cloud/node-role: management` | NGINX, Argo CD, cert-manager, OpenBao |
| Worker | `custom.kaas.infomaniak.cloud/node-role: worker` | Application workloads |

**Your application pods must run on worker nodes.** See the
[Node Scheduling](#3-node-scheduling) section for how to configure this.

---

## Constraints and Requirements

### 1. Namespace

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
    # example: enable OpenBao agent injection for all pods in this namespace
    bao.openbao.org/agent-injection: "enabled"
```

And set `CreateNamespace=false` in your sync options to prevent Argo CD
from overwriting it:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=false
```

---

### 2. Secrets

**Never commit plain secrets to GitHub.** Secrets are managed via
OpenBao and injected directly into pods as files by the OpenBao Agent
Injector. **Secrets are never stored as Kubernetes Secrets** — they
exist only in OpenBao and in the memory of your running pods.

```
OpenBao (secret store)
    → Agent Injector (mutating webhook — auto-injects sidecar)
        → OpenBao Agent sidecar (fetches secrets at pod startup)
            → secrets written as files to /bao/secrets/ in your pod
                → your application reads secrets from files
```

#### Step 1 — configure openbao for the application

you need

- Your application name (used as the OpenBao path: `secret/your-app`)
- Your namespace name
- The list of secrets your application needs

- Create a KV secret path for your application in OpenBao
- Create an OpenBao policy granting read access to your path
- Create a Kubernetes auth role binding your service account to the policy
- Provide you with credentials to access the OpenBao UI

#### Step 2 — Store your secrets via the OpenBao UI

Access the OpenBao UI at `https://openbao.your-domain.com` using the
credentials for your application:

1. Navigate to **Secrets → secret → your-app**
2. Click **Create new version**
3. Add your key-value pairs (e.g. `db-password`, `api-key`)
4. Click **Save**

#### Step 3 — Annotate your pods for secret injection

Add annotations to your pod template in your Helm values. The OpenBao
Agent Injector automatically detects these annotations via a mutating
webhook and injects a sidecar that fetches secrets from OpenBao:

```yaml
# In your values.yaml
podAnnotations:
  # Enable secret injection
  bao.openbao.org/agent-inject: "true"

  # OpenBao auth role (must match the role created by the platform team)
  bao.openbao.org/role: "your-app"

  # One pair of annotations per secret file:
  # bao.openbao.org/agent-inject-secret-<filename>: "<openbao-path>"
  # bao.openbao.org/agent-inject-template-<filename>: "<template>"

  # Example: inject db-password as /bao/secrets/db-password
  bao.openbao.org/agent-inject-secret-db-password: "secret/data/your-app"
  bao.openbao.org/agent-inject-template-db-password: |
    {{- with secret "secret/data/your-app" -}}
    {{ .Data.data.db-password }}
    {{- end }}

  # Example: inject all secrets as a config file /bao/secrets/config
  bao.openbao.org/agent-inject-secret-config: "secret/data/your-app"
  bao.openbao.org/agent-inject-template-config: |
    {{- with secret "secret/data/your-app" -}}
    DB_PASSWORD={{ .Data.data.db-password }}
    API_KEY={{ .Data.data.api-key }}
    {{- end }}
```

Secrets are available inside your pod at `/bao/secrets/<filename>`.

#### Step 4 — Read secrets from files in your application

Configure your application to read secrets from files rather than
environment variables:

```yaml
# Example: pass secret file path as environment variable
env:
  - name: DB_PASSWORD_FILE
    value: /bao/secrets/db-password
```

Or source the config file directly if your application supports it:

```yaml
# Example: sourcing all secrets from a config file
command:
  - sh
  - -c
  - |
    export DB_PASSWORD=$(cat /bao/secrets/db-password)
    exec your-app-entrypoint
```

#### Important notes on secret injection

- The injector runs as a **mutating webhook** — pods without the
  `bao.openbao.org/agent-inject: "true"` annotation are not affected
- The agent sidecar runs alongside your container and renews secrets
  automatically before they expire
- If OpenBao is sealed or unreachable, pods will **fail to start** —
  contact the platform team if this happens
- Secrets are written to an **in-memory tmpfs volume** shared between
  the agent sidecar and your container — they are never written to disk

---

### 3. Node Scheduling

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

### 4. Service Type

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

### 5. Ingress

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

### 6. Replica Management

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

### 7. Liveness and Readiness Probes

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

### 8. Persistence

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
│   └── values.yaml             # Helm chart values (including injector annotations)
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
        └── values.yaml         # your custom values including podAnnotations
```

Note there is no `external-secret.yaml` — secrets are injected directly
into pods by the OpenBao Agent Injector via pod annotations defined in
`values.yaml`. No Kubernetes Secret resources are created.

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

Select the container from the dropdown if your pod has multiple
containers (e.g. your app + the OpenBao agent sidecar).

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
- [ ] OpenBao access requested from the platform team
- [ ] Secrets stored via the OpenBao UI
- [ ] Pod annotations added for OpenBao Agent Injector (`bao.openbao.org/agent-inject: "true"`)
- [ ] Application reads secrets from files at `/bao/secrets/` not environment variables
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
| Secret injection failing | Check **Logs → vault-agent-init** container in Argo CD UI |
| Secrets not refreshing | Check **Logs → vault-agent** container in Argo CD UI |
| Certificate not issuing | Check the `certificate` resource status in Argo CD UI |
| Pod not scheduling | Check pod **Events** in Argo CD UI for node affinity errors |
| OpenBao sealed or unreachable | Contact platform team |
| Infrastructure issues (nodes, networking) | Contact platform team |
| OpenBao access, policies and auth roles | Contact platform team |
| Argo CD access and GitOps repository | Contact platform team |
| Need a pod restarted | Contact platform team or push a trivial Git change |