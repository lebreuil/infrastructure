# Agent guidance

## Terraform scope

The `terraform/` directory is the infrastructure-as-code boundary for this
repository. It provisions an Infomaniak managed Kubernetes cluster and node
pools, OpenStack network lookups, NGINX Ingress, cert-manager, Cloudflare DNS
and Access, Argo CD, OpenBao, External Secrets, and the example application
resources. Application deployment manifests and application-owned Helm values
belong in the application repositories and `gitops/`, not in this directory.

Keep changes focused on the relevant Terraform file:

- `kaas.tf` — cluster and management/worker node pools.
- `network.tf` — provider lookups needed for the cluster network and Cloudflare
  access data.
- `ingress-controller.tf`, `cert-manager.tf`, and `nginx-values.yaml` —
  ingress and TLS infrastructure.
- `argocd.tf` and `argocd-values.yaml` — Argo CD and app-of-apps bootstrap.
- `openbao.tf`, `openbao-config.tf`, and `openbao-values.yaml` — OpenBao
  deployment and platform policies/authentication.
- `app-*.tf` — application-specific Kubernetes, OpenBao, DNS, and Cloudflare
  Access resources.
- `providers.tf`, `versions.tf`, and `variables.tf` — provider wiring,
  constraints, and inputs.
- `deploy.sh` — the ordered first-deployment helper; keep its targets aligned
  with resource names when Terraform resources change.

## Safety and secrets

- Never commit `terraform.tfvars`, state files, plan files, credentials, API
  tokens, OpenBao keys, or root tokens. The root `.gitignore` is intentionally
  configured to exclude these files.
- Treat Terraform plans and state as sensitive: do not paste them into issues,
  pull requests, or chat.
- Use the existing sensitive variables and provider authentication mechanisms.
  Do not hard-code credentials or create new Kubernetes Secrets for
  application secrets. External Secrets Operator is the intended mechanism for
  synchronizing OpenBao values into namespace-local Kubernetes Secrets.
- `clouds.yaml` is expected at `~/.config/openstack/clouds.yaml`; use the
  configured `os_cloud` variable rather than embedding OpenStack credentials.
- OpenBao is Vault API-compatible and is configured through the aliased
  `vault.terraform` provider. Changes that require a live OpenBao connection
  must be made only after OpenBao has been initialized and unsealed.
- Application secret values, generated credentials, and application tokens are
  owned by application teams. Do not create them in Terraform or store them in
  Terraform state.
- Application teams must never receive the OpenBao root token or Terraform
  token. Provide only the application-specific OpenBao access and workflow.

## Deployment workflow

Run Terraform commands from `terraform/`. For a new cluster, use the phased
workflow in `deploy.sh` because provider data and Kubernetes resources depend
on earlier resources existing:

1. Cluster (`infomaniak_kaas.cluster`).
2. Management and worker node pools.
3. Network lookups, NGINX Ingress, cert-manager, and the Let's Encrypt issuer.
4. OpenBao deployment, then manually initialize and unseal OpenBao.
5. OpenBao KV/auth configuration and policies.
6. Argo CD, ingress, DNS, and Cloudflare Access.
7. Store the GitHub App credentials in OpenBao, restart the Argo CD repo
   server, and bootstrap the app-of-apps.
8. Apply remaining resources.

Before the first apply, create a local `terraform.tfvars` from the variables
in `variables.tf`, run `terraform init`, and confirm the required provider
credentials and `clouds.yaml` are available. The helper supports
`./deploy.sh`, `./deploy.sh --from N`, and `./deploy.sh --only N`. Do not
remove a manual pause or replace a targeted phase with a full apply unless the
dependency order has been verified.

After the initial deployment, prefer the normal dependency graph:

```bash
terraform plan
terraform apply
```

Use targeted applies only for deliberate recovery or bootstrap work, and
always inspect the plan before applying changes to shared infrastructure.

## Change and validation conventions

- Preserve explicit `depends_on` relationships and the management/worker node
  separation. Management nodes host platform services; worker nodes host
  application workloads.
- When onboarding an application, keep its platform resources together in an
  `app-*.tf` file. Terraform owns the dedicated Kubernetes namespace, ESO
  service account and namespace-scoped RBAC, OpenBao namespace and policies,
  Kubernetes auth role, Ingress, DNS, and Cloudflare Access configuration.
- Application owners own their application repository, Helm values,
  namespace-local `SecretStore` and `ExternalSecret`, and secret values in
  OpenBao. Application Services must use `ClusterIP`, and workloads must target
  worker nodes.
- The platform repository contains one app-of-apps at
  `gitops/app-of-apps.yaml`. It watches the `applications` directory in
  `https://github.com/lebreuil/applications`. Add application Argo CD
  `Application` manifests there; do not add one-off registrations or another
  app-of-apps to this repository.
- Hand application teams the dedicated `APPLICATION_SECRETS.md` guide. The
  platform-only bootstrap and token hierarchy remain in
  `SECRETS_MANAGEMENT.md`.
- Keep Helm values in the corresponding `*-values.yaml` file. Provider version
  constraints in `versions.tf` are intentional; in particular, do not upgrade
  the Helm provider without checking the documented schema-validation issue.
- Format changed Terraform files with `terraform fmt`. Validate syntax and
  provider/resource configuration with `terraform validate` after
  `terraform init` has been run.
- Review `terraform plan` output for unintended replacements, networking
  changes, access-policy changes, and secret exposure before applying.
- Update the root README or related operational documentation when a change
  alters deployment order, required variables, onboarding steps, or recovery
  procedures.