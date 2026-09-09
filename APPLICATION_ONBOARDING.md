# Application Onboarding Guide

This guide is for application owners deploying workloads onto the shared
platform. It only covers the parts you need to know and the resources you are
provided with.

Developers do not have direct access to the cluster. Application owners work
through:

- GitHub for application manifests and Helm values
- Argo CD for deployment status and troubleshooting
- OpenBao for application secret values

The platform team handles the shared infrastructure and the bootstrap
configuration for OpenBao, Argo CD, and ingress/TLS. Application owners only
need to manage their own application repository, deployment manifests, and the
secret values assigned to that application.

---

## What the platform team provides

During onboarding, the platform team typically provides:

- a dedicated Kubernetes namespace for your application
- an OpenBao namespace and secret path for your application
- the Kubernetes auth role and service account used by External Secrets
  Operator to read secrets
- a DNS name based on your application name
- access to the Argo CD UI and the OpenBao UI for your application
- the shared ingress and TLS configuration

If you are missing any of these, ask the platform team before you start the
application deployment.

---

## What application owners are responsible for

As the application owner, you are responsible for:

- your application repository and deployment manifests
- Helm values for your application
- the Service and application configuration
- the `SecretStore` and `ExternalSecret` resources in your namespace
- the secret values stored in OpenBao
- checking deployment health in Argo CD

---

## Namespace

The platform team creates a dedicated Kubernetes namespace for your
application through Terraform. Do not define or create the namespace in your
application repository.

---

## Worker node placement

Application pods must schedule on worker nodes.

Add this to your Helm values or workload configuration:

```yaml
nodeSelector:
  custom.kaas.infomaniak.cloud/node-role: "worker"
```

If your chart includes subcharts such as PostgreSQL, Redis, or Valkey, apply the
same selector to each relevant component.

---

## Service

Use a `ClusterIP` service. Do not use `LoadBalancer` or `NodePort`.

```yaml
service:
  type: ClusterIP
```

The platform team creates the Ingress and TLS configuration and assigns the DNS
name based on your application name. You do not need to create DNS or Ingress
resources.

---

## Secrets and OpenBao

See the [Application Secrets Guide](APPLICATION_SECRETS.md) for the complete
application-team secret workflow.

Do not commit plain secrets to GitHub.

The platform team creates the OpenBao namespace, permissions, and the
namespace-scoped sync account for your application. You are expected to:

1. store secret values in the OpenBao UI or through the application secret
   workflow provided by the platform team
2. declare a namespace-local `SecretStore` and `ExternalSecret` in your
   application repository
3. reference the synchronized Kubernetes Secret in your application

Example:

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

Then reference the resulting secret from your application values:

```yaml
envFrom:
  - secretRef:
      name: your-app-secrets
```

Use the namespace-local secret only. Do not define a `ClusterSecretStore` or
reference secrets across namespaces.

---

## Argo CD

Your application is deployed through Argo CD. You are provided with the access
for the Argo CD UI and the repository/application registration needed for your
service.

Use Argo CD to:

- confirm the application is synced
- watch the health status of pods and resources
- inspect events and logs when a deployment fails
- confirm the app matches what is in Git

Typical application repository structure:

```text
your-app-repo/
├── deploy/
│   ├── values.yaml
│   └── secrets.yaml
└── Chart.yaml
```

The platform team manages the shared infrastructure; your job is to keep the
application repository and deployment state in sync with Git.

---

## Minimum checklist before go-live

Before production deployment, confirm that your application:

- runs in the correct namespace
- has a `nodeSelector` for worker nodes
- uses `ClusterIP` Service and no `LoadBalancer`
- stores secrets in OpenBao and references the synchronized Secret
- is registered in Argo CD and shows healthy status

If anything is unclear, ask the platform team. You are not expected to manage
Terraform, cluster bootstrapping, or the shared platform components.
