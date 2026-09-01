
# OpenBao Bootstrap and Application Secrets

This repository's `scripts/` directory contains the scripts used to bootstrap
OpenBao and create application credentials and secrets outside of Terraform.

The goal is to keep generated credentials and secret values out of the
Terraform configuration and Terraform state.

## Architecture

The process is divided into three stages:

```text
                    OpenBao
                       |
                       v
              Initialize / Unseal
                       |
                       v
        +-----------------------------+
        |  1. openbao-bootstrap.py    |
        |                             |
        |  Root token                 |
        |       |                     |
        |       +--> Terraform policy |
        |       |                     |
        |       +--> Terraform token  |
        +-------------+---------------+
                      |
                      v
                 Terraform
                      |
          +-----------+-----------+
          |                       |
          v                       v
      Namespaces              Policies
          |                       |
          +-----------+-----------+
                      |
                      v
        +-----------------------------+
        |  2. create-app-token.py     |
        |                             |
        |  Terraform token            |
        |       |                     |
        |       +--> application token|
        +-------------+---------------+
                      |
                      v
        +-----------------------------+
        |  3. app-secrets-init.py     |
        |                             |
        |  Application token          |
        |       |                     |
        |       +--> generated secrets|
        +-----------------------------+
```

## Why three steps?

The credentials have different responsibilities and lifetimes.

### 1. Root token

The OpenBao root token is used only during the initial bootstrap.

It is used to create the Terraform policy and Terraform token.

The root token should **not** be used by Terraform or applications.

### 2. Terraform token

The Terraform token is used by the Terraform pipeline to manage OpenBao.

Terraform can create and manage:

* child namespaces
* secrets engines
* authentication backends
* GitHub authentication
* Kubernetes authentication
* authentication roles/configuration
* ACL policies
* application tokens

The Terraform token is therefore highly privileged, but it is not the OpenBao root token.

### 3. Application token

Each application receives its own token.

The token is created in the application's namespace using the policy created by Terraform, for example:

```text
app_write
```

The application token is then used by `app-secrets-init.py` to write and read
the application's secrets.

Applications never receive the Terraform token.

---

# Prerequisites

Install the dependencies used by the scripts:

```bash
pip install hvac requests
```

`openbao-bootstrap.py` uses `hvac`. `create-app-token.py` and
`app-secrets-init.py` call the OpenBao HTTP API directly through `requests`.

The OpenBao server must already be:

1. deployed
2. initialized
3. unsealed

Cloudflare Access must also allow the bootstrap machine to reach OpenBao.

---

# Environment files

Do not store credentials in Git.

A recommended setup is to have two local environment files.

## Bootstrap environment

For example:

```text
.env.bootstrap
```

```bash
OPENBAO_ADDR=https://openbao.example.com
OPENBAO_ROOT_TOKEN=...

CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...

TERRAFORM_POLICY=terraform
TERRAFORM_TOKEN_TTL=720h
```

Add the file to `.gitignore`:

```gitignore
.env
.env.*
```

Load it with:

```bash
set -a
source .env.bootstrap
set +a
```

The `set -a` option automatically exports variables loaded from the file.

---

# Step 1 — Bootstrap the Terraform token

After OpenBao has been initialized and unsealed, run:

```bash
set -a
source .env.bootstrap
set +a

python3 openbao-bootstrap.py
```

The script:

1. authenticates with the root token
2. creates or updates the `terraform` policy
3. creates a renewable Terraform token
4. displays the token

Example:

```text
✓ Root token authenticated
✓ Terraform policy 'terraform' created/updated
✓ Terraform token created
```

The generated token is then saved as:

```bash
OPENBAO_TERRAFORM_TOKEN=...
```

Store this token securely.

Do not commit it to Git.

---

# Terraform policy

The bootstrap script creates the Terraform policy.

The policy allows Terraform to manage child namespaces and their
configuration.

## Namespaces

Terraform can create, update, delete and list namespaces:

```hcl
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

## Secrets engines

Terraform can manage secrets engines in child namespaces:

```hcl
path "+/sys/mounts/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list",
    "sudo"
  ]
}
```

## Authentication backends

Terraform can enable, configure and remove authentication methods:

```hcl
path "+/sys/auth/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list",
    "sudo"
  ]
}
```

This supports authentication methods such as:

* GitHub
* Kubernetes
* OIDC
* JWT
* AppRole
* Token

Terraform can also configure the endpoints of those authentication
methods:

```hcl
path "+/auth/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list",
    "sudo"
  ]
}
```

## ACL policies

Terraform can create and manage ACL policies inside child namespaces:

```hcl
path "+/sys/policies/acl/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list"
  ]
}
```

## Application tokens

The Terraform token can create application tokens inside child namespaces:

```hcl
path "+/auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}
```

The `sudo` capability is important because OpenBao requires root or sudo
privileges when a token from a parent namespace directly creates a token in
a child namespace.

---

# Step 2 — Create an application token

Once Terraform has created the application namespace and its policies,
create the application token.

Example environment:

```bash
OPENBAO_ADDR=https://openbao.example.com

OPENBAO_ROOT_TOKEN=...

BAO_NAMESPACE=app
BAO_POLICY=app_write
TOKEN_TTL=720h

CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...
```

For the application-token script, the administrative token should be the
Terraform token:

```bash
OPENBAO_ROOT_TOKEN=<terraform-token>
```

Then:

```bash
set -a
source .env.admin
set +a

python3 create-app-token.py
```

The token is created in:

```text
app
```

using:

```text
app_write
```

The generated application token should be stored securely.

It becomes:

```bash
OPENBAO_APP_TOKEN=...
```

---

# Step 3 — Create application secrets

The application secrets script uses the application token.

Example:

```bash
OPENBAO_ADDR=https://openbao.example.com
OPENBAO_APP_TOKEN=...

BAO_NAMESPACE=app
SECRET_MOUNT=secret
SECRET_KEY=config

CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...
```

Run:

```bash
set -a
source .env.app
set +a

python3 app-secrets-init.py
```

The checked-in `.env.app` sets `BAO_NAMESPACE=app`. Always set the namespace
to the namespace where the application token was created.

The script uses the OpenBao KV v2 API directly. It verifies the application
token with `auth/token/lookup-self`, reads and writes
`<mount>/data/<secret-key>`, and sends the Cloudflare Access headers with every
request. Set `DEBUG=1` to display request metadata and response status codes;
secret values are never logged.

The script generates secrets such as:

```text
secret-key
superuser-password
superuser-api-token
postgresql-password
valkey-password
email-password
```

and stores them in:

```text
app/secret/config
```

Secret values are never printed by the script.

---

# Credential hierarchy

The final credential hierarchy is:

```text
Root token
    |
    +-- creates Terraform policy
    |
    +-- creates Terraform token
              |
              +-- Terraform manages namespaces
              |
              +-- Terraform manages auth backends
              |
              +-- Terraform manages secrets engines
              |
              +-- Terraform manages ACL policies
              |
              +-- creates application tokens
                         |
                         +-- application secrets
```

Applications should never have access to:

```text
Root token
Terraform token
```

Applications should only receive their own application token.

---

# Cloudflare Access

All scripts support Cloudflare Access service authentication.

The following environment variables are required:

```bash
CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...
```

The scripts automatically add:

```http
CF-Access-Client-Id: ...
CF-Access-Client-Secret: ...
```

to OpenBao requests.

There is therefore no need to manually add these headers to individual
API calls.

---

# Git security

At minimum, add the following to `.gitignore`:

```gitignore
.env
.env.*
!.env.example
```

You can provide an example file:

```text
.env.example
```

containing only placeholders:

```bash
OPENBAO_ADDR=https://openbao.example.com

OPENBAO_ROOT_TOKEN=
OPENBAO_TERRAFORM_TOKEN=
OPENBAO_APP_TOKEN=

CF_ACCESS_CLIENT_ID=
CF_ACCESS_CLIENT_SECRET=

BAO_NAMESPACE=app
SECRET_MOUNT=secret
SECRET_KEY=config
```

Never commit:

* the root token
* the Terraform token
* application tokens
* Cloudflare Access secrets
* generated application passwords
* `.env` files containing real credentials

---

# Recommended operational workflow

## Initial OpenBao deployment

```text
1. Deploy OpenBao
2. Initialize OpenBao
3. Unseal OpenBao
4. Run openbao-bootstrap.py
5. Store Terraform token securely
6. Run Terraform
```

## New application

```text
1. Terraform creates namespace
2. Terraform creates application policy
3. Terraform configures auth/secrets engines
4. Run create-app-token.py
5. Store application token securely
6. Run app-secrets-init.py
7. Deploy application
```

## Important

Terraform should manage the OpenBao infrastructure and policy definitions,
but should not need to manage generated application passwords or application
tokens.

This keeps dynamically generated credentials outside Terraform state and
makes it possible to rotate application credentials independently of the
infrastructure deployment.
