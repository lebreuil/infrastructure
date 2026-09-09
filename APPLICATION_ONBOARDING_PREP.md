# Application Onboarding Preparation

This guide is for the platform team. It describes the infrastructure and
access configuration to complete before handing an application to its owners.
Application owners should use [Application Onboarding](APPLICATION_ONBOARDING.md)
for the resources and constraints that apply to them.

Application-specific platform resources belong in a dedicated `terraform/app-*.tf`
file. Application manifests and Helm values belong in the application
repository. Argo CD application registrations belong in the
`applications` directory of the
[`lebreuil/applications`](https://github.com/lebreuil/applications) repository.

---

## Information to collect

Before changing Terraform, obtain the following from the application owner:

- application name and desired Kubernetes namespace name
- GitHub repository URL and deployment path
- Kubernetes Service name and port used by the application
- application owner and operational contact
- Cloudflare Access identity and access-policy requirements

Use the application name consistently for the Kubernetes namespace, OpenBao
namespace, DNS name, and Argo CD Application name unless there is an explicit
reason not to.

---

## Platform resources to add

Add the application resources to its `terraform/app-*.tf` file.

### Kubernetes namespace and secret-sync identity

Create:

- a dedicated Kubernetes namespace
- a dedicated service account for External Secrets Operator authentication
- a namespace-scoped Role allowing the ESO controller to use that service
  account and manage only the application's synchronized Secret resources
- the matching RoleBinding to the ESO controller service account

Do not grant the application workload service accounts OpenBao access. The ESO
sync service account is deliberately separate from application workload
identities.

### OpenBao namespace and policies

Create an isolated OpenBao namespace for the application containing:

- a KV v2 mount named `secret`
- a Kubernetes auth backend configured for the cluster
- a read policy limited to the application's `secret/config` value
- a write policy for the application owner, limited to that OpenBao namespace
- a Kubernetes auth role bound only to the namespace-local ESO service account
  and the read policy

Preserve the least-privilege policy shape used by the existing application
resources. Do not place generated passwords, application tokens, or secret
values in Terraform configuration or state.

### Ingress and DNS

Create the application's Ingress in Terraform. The platform assigns the DNS
name from the application name and the shared base domain.

The Ingress should:

- use the shared NGINX ingress class
- route to the Service name and port supplied by the application owner
- use the platform Let's Encrypt issuer
- enable HTTPS

Create the matching Cloudflare DNS record from the Ingress load-balancer
address. Do not ask application owners to create DNS or Ingress resources in
their application repository.

### Cloudflare Access

Create a Cloudflare Zero Trust Access application for the assigned hostname and
attach the approved identity provider and access policy. Confirm the required
Cloudflare Access settings with the platform owner before applying.

### Argo CD registration

The platform repository contains one unique app-of-apps `Application` in
[`gitops/app-of-apps.yaml`](gitops/app-of-apps.yaml). It watches the
`applications` directory in the
[`lebreuil/applications`](https://github.com/lebreuil/applications) repository.
Do not add one-off application registrations to this repository.

Register each new application by adding an Argo CD `Application` manifest to
the `applications` directory of the applications repository with:

- the application repository URL
- the approved target revision and deployment path
- the Terraform-created namespace as destination
- the repository's agreed sync policy

Do not create another app-of-apps resource. Do not configure Argo CD to create
the namespace when Terraform owns it. Ensure the application repository
contains the namespace-local `SecretStore` and `ExternalSecret` manifests
expected by the platform resources.

---

## Apply and validate the platform configuration

From `terraform/`:

1. Run `terraform fmt` on changed Terraform files.
2. Run `terraform validate`.
3. Review `terraform plan` for namespace, RBAC, OpenBao policy, DNS, Access,
   and ingress changes.
4. Confirm the plan contains no application secret values or generated tokens.
5. Apply the approved plan.

OpenBao must already be initialized and unsealed before applying resources that
use the `vault.terraform` provider.

After applying, verify:

- the Kubernetes namespace exists
- the ESO service account and RoleBinding exist
- the OpenBao namespace, KV mount, auth backend, policy, and role exist
- the Ingress has an address and its certificate becomes Ready
- the DNS record resolves to the shared ingress endpoint
- Cloudflare Access protects the hostname when required
- Argo CD can read the repository and sees the Application

---

## Application secret handoff

Application secret creation is the responsibility of the application team.
After Terraform has created the OpenBao namespace, policies, and Kubernetes
auth role, provide the application team with the OpenBao access and secret path
they need to manage their values.

The platform team must not create or store application secret values,
generated credentials, or application tokens in Terraform configuration or
state. Application owners must never receive the Terraform token or the
OpenBao root token.

Hand the application team the [Application Secrets Guide](APPLICATION_SECRETS.md).
The platform-only bootstrap and token hierarchy remains documented in
[Secrets Management](SECRETS_MANAGEMENT.md).

---

## Handoff to the application owner

Provide the application owner with:

- the assigned Kubernetes namespace
- the assigned application DNS name
- the Argo CD UI URL and application name
- the OpenBao UI URL and application namespace
- the fixed ESO service account name and OpenBao auth role
- the secret path and expected key format
- the repository path and deployment expectations

Confirm that the owner understands:

- the namespace and Ingress are platform-managed
- application pods must target worker nodes
- application Services must use `ClusterIP`
- secrets must be stored in OpenBao, not Git
- deployment status and logs are viewed through Argo CD

---

## Onboarding completion checklist

- [ ] Application inputs and owner contact recorded
- [ ] Dedicated `terraform/app-*.tf` resources added
- [ ] Namespace and ESO RBAC configured
- [ ] OpenBao namespace, KV mount, policies, and auth role configured
- [ ] Ingress and assigned DNS record configured
- [ ] Cloudflare Access configured where required
- [ ] Argo CD Application registered in `gitops/`
- [ ] Terraform formatted, validated, planned, and applied
- [ ] Certificate and DNS verified
- [ ] OpenBao access and secret handoff details provided to the application team
- [ ] Argo CD application is synced and healthy
- [ ] Handoff details sent to the application owner
