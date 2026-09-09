# Application Secrets Guide

This guide is for application teams. It explains how to store application
secrets in OpenBao and make them available to workloads through External
Secrets Operator (ESO).

The platform team manages OpenBao, ESO, namespace permissions, and the
application access configuration. You do not need Terraform, the OpenBao root
token, or the Terraform token.

## What the platform team provides

The platform team gives you:

- the OpenBao UI URL
- your OpenBao namespace
- the secret path to use, normally `secret/config`
- application access credentials or the approved secret-initialisation
  workflow
- the ESO service account name and OpenBao auth role
- the Kubernetes namespace where the synchronized Secret is created

Ask the platform team if any of these details are missing.

## Store values in OpenBao

Do not commit secret values to GitHub or put them in Helm values.

1. Open the OpenBao UI.
2. Select your application's OpenBao namespace.
3. Open **Secrets → secret → config**.
4. Create the secret if it does not exist, or create a new version if it does.
5. Add the required key-value pairs.
6. Save the secret.

The application secret is stored at the KV v2 path `secret/config`. Keep all
application values in this application namespace. Do not use another
application's namespace or secret path.

If the platform team gives you an approved script-based workflow instead of UI
access, follow that workflow and keep its environment files and tokens out of
Git.

### Script-based secret initialization

If the platform team provides an application token and access to the
initialization scripts, use the application token to create or update the
application's `secret/config` entry:

```bash
OPENBAO_ADDR=https://openbao.your-domain.com
OPENBAO_APP_TOKEN=...

BAO_NAMESPACE=your-app
SECRET_MOUNT=secret
SECRET_KEY=config

CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...
```

Export these variables from a local, uncommitted environment file and run:

```bash
set -a
source .env.app
set +a
python3 app-secrets-init.py
```

The script authenticates with the application token and writes generated
values, such as application keys and database passwords, to
`your-app/secret/config`. Secret values are not printed. Set `BAO_NAMESPACE`
to the OpenBao namespace assigned to your application; do not use `app` unless
that is the namespace provided by the platform team.

Never commit `.env.app`, the application token, Cloudflare Access credentials,
or generated secret values. The script supports `DEBUG=1` for request metadata
and status codes, but it does not log secret values.

## Synchronize the secret to Kubernetes

Commit a namespace-local `SecretStore` and `ExternalSecret` to the application
repository. Use the exact namespace, service account, and auth role supplied by
the platform team.

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

The `SecretStore`, `ExternalSecret`, and target Kubernetes Secret must remain
in the application namespace. Do not define a `ClusterSecretStore` or use a
cross-namespace secret reference.

## Use the synchronized Secret

Reference the Kubernetes Secret from your Helm values or workload manifest:

```yaml
envFrom:
  - secretRef:
      name: your-app-secrets
```

For one key only, use `secretKeyRef` instead:

```yaml
env:
  - name: SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: your-app-secrets
        key: secret-key
```

ESO refreshes the Kubernetes Secret periodically. Applications may need to
restart before they read updated values from environment variables.

## Check and troubleshoot

Use Argo CD to check the `SecretStore`, `ExternalSecret`, and generated Secret.

- If the `ExternalSecret` is `Ready`, synchronization succeeded.
- If it is not `Ready`, inspect its events and contact the platform team.
- If OpenBao is sealed or unavailable, the last successfully synchronized
  Kubernetes Secret is retained and the platform team must restore OpenBao.
- If the application does not see a changed environment variable, restart it
  through the normal GitOps workflow.

## Secret handling rules

- Never commit secrets, tokens, `.env` files, or generated credentials.
- Never request or use the OpenBao root token or Terraform token.
- Keep application secrets in the application's OpenBao namespace.
- Rotate values by creating a new OpenBao secret version and restarting
  workloads when required.

## Application team checklist

- [ ] OpenBao namespace and UI access received
- [ ] Required values stored at `secret/config`
- [ ] `SecretStore` committed with the supplied auth role and service account
- [ ] `ExternalSecret` committed in the application namespace
- [ ] Workloads reference the generated Kubernetes Secret
- [ ] Argo CD reports the `ExternalSecret` as `Ready`
- [ ] No secret values or credentials are committed to Git
