#!/usr/bin/env python3
"""
openbao-bootstrap.py — Bootstrap the Terraform token in OpenBao.

Run this script once after OpenBao has been initialized and unsealed.

The real OpenBao root token is required.

The script:
    1. Authenticates using the root token.
    2. Creates/updates the Terraform policy.
    3. Creates a Terraform token using that policy.
    4. Prints the Terraform token once.

Requirements:
    pip install hvac

Required environment variables:
    OPENBAO_ADDR
    OPENBAO_ROOT_TOKEN
    CF_ACCESS_CLIENT_ID
    CF_ACCESS_CLIENT_SECRET

Optional environment variables:
    TERRAFORM_POLICY=terraform
    TERRAFORM_TOKEN_TTL=720h

Usage:
    python3 openbao-bootstrap.py
"""

import os
import sys

import hvac


# ============================================================
# Configuration
# ============================================================

OPENBAO_ADDR = os.environ.get("OPENBAO_ADDR", "").rstrip("/")
ROOT_TOKEN = os.environ.get("OPENBAO_ROOT_TOKEN", "")

TERRAFORM_POLICY = os.environ.get(
    "TERRAFORM_POLICY",
    "terraform",
)

TERRAFORM_TOKEN_TTL = os.environ.get(
    "TERRAFORM_TOKEN_TTL",
    "720h",
)

CF_ACCESS_CLIENT_ID = os.environ.get(
    "CF_ACCESS_CLIENT_ID",
    "",
)

CF_ACCESS_CLIENT_SECRET = os.environ.get(
    "CF_ACCESS_CLIENT_SECRET",
    "",
)


# ============================================================
# Terraform policy
# ============================================================

TERRAFORM_POLICY_HCL = r'''
# ============================================================
# Root namespace
# ============================================================

# Manage child namespaces
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/namespaces" {
  capabilities = ["read", "list"]
}


# ============================================================
# Token management
# ============================================================

# Create tokens in the root namespace
path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/create/*" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/lookup" {
  capabilities = ["create", "update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}


# ============================================================
# Child namespaces
# ============================================================

# Secrets engines
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

path "+/sys/mounts" {
  capabilities = ["read", "list"]
}


# Enable/configure authentication methods
#
# Examples:
#   GitHub
#   Kubernetes
#   AppRole
#   OIDC
#   JWT
#   Token
#
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

path "+/sys/auth" {
  capabilities = ["read", "list"]
}


# Configure authentication method endpoints
#
# Examples:
#   auth/github/config
#   auth/github/map/teams/...
#   auth/kubernetes/config
#   auth/kubernetes/role/...
#
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


# ============================================================
# ACL policies
# ============================================================

path "+/sys/policies/acl/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list"
  ]
}

path "+/sys/policies/acl" {
  capabilities = ["read", "list"]
}


# ============================================================
# Secrets engines
# ============================================================

# KV and other paths mounted at "secret"
path "+/secret/*" {
  capabilities = [
    "create",
    "read",
    "update",
    "delete",
    "list"
  ]
}


# ============================================================
# Application token management
# ============================================================

# OpenBao requires root/sudo privileges when a token from a
# parent namespace directly creates a token in a child namespace.
path "+/auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

path "+/auth/token/lookup-self" {
  capabilities = ["read"]
}

path "+/auth/token/renew-self" {
  capabilities = ["update"]
}

path "+/auth/token/revoke-self" {
  capabilities = ["update"]
}
'''


# ============================================================
# Output helpers
# ============================================================

GREEN = "\033[0;32m"
RED = "\033[0;31m"
RESET = "\033[0m"


def info(message):
    print(f"{GREEN}✓ {message}{RESET}")


def error(message):
    print(f"{RED}✗ {message}{RESET}", file=sys.stderr)
    sys.exit(1)


# ============================================================
# OpenBao client
# ============================================================

def get_client():
    required = {
        "OPENBAO_ADDR": OPENBAO_ADDR,
        "OPENBAO_ROOT_TOKEN": ROOT_TOKEN,
        "CF_ACCESS_CLIENT_ID": CF_ACCESS_CLIENT_ID,
        "CF_ACCESS_CLIENT_SECRET": CF_ACCESS_CLIENT_SECRET,
    }

    missing = [
        name
        for name, value in required.items()
        if not value
    ]

    if missing:
        error(
            "Missing environment variable(s): "
            + ", ".join(missing)
        )

    # IMPORTANT:
    # No namespace is specified here.
    #
    # The root token belongs to the root namespace.
    client = hvac.Client(
        url=OPENBAO_ADDR,
        token=ROOT_TOKEN,
    )

    # Cloudflare Access service-token headers.
    client.adapter.session.headers.update({
        "CF-Access-Client-Id": CF_ACCESS_CLIENT_ID,
        "CF-Access-Client-Secret": CF_ACCESS_CLIENT_SECRET,
    })

    return client


# ============================================================
# Main
# ============================================================

def main():
    print()
    print("OpenBao bootstrap")
    print("=" * 60)
    print(f"  OpenBao URL : {OPENBAO_ADDR}")
    print(f"  Policy      : {TERRAFORM_POLICY}")
    print(f"  Token TTL   : {TERRAFORM_TOKEN_TTL}")
    print()

    client = get_client()

    # --------------------------------------------------------
    # Verify root token
    # --------------------------------------------------------

    try:
        if not client.is_authenticated():
            error("OpenBao root token is not authenticated")
    except Exception as exc:
        error(f"Cannot connect to OpenBao: {exc}")

    info("Root token authenticated")

    # --------------------------------------------------------
    # Create/update Terraform policy
    # --------------------------------------------------------

    try:
        response = client.sys.create_or_update_policy(
            name=TERRAFORM_POLICY,
            policy=TERRAFORM_POLICY_HCL,
        )

        if not isinstance(response, dict):
            response.raise_for_status()

    except Exception as exc:
        error(
            f"Failed to create/update Terraform policy: {exc}"
        )

    info(
        f"Terraform policy '{TERRAFORM_POLICY}' "
        "created/updated"
    )

    # --------------------------------------------------------
    # Create Terraform token
    # --------------------------------------------------------

    try:
        response = client.auth.token.create(
            policies=[TERRAFORM_POLICY],
            ttl=TERRAFORM_TOKEN_TTL,
            renewable=True,
            no_default_policy=True,
            display_name="terraform",
        )

        if not isinstance(response, dict):
            response.raise_for_status()
            response = response.json()

        token = response["auth"]["client_token"]

    except Exception as exc:
        error(f"Failed to create Terraform token: {exc}")

    # --------------------------------------------------------
    # Output token
    # --------------------------------------------------------

    print()
    info("Terraform token created")
    print()

    print("=" * 70)
    print("IMPORTANT — SAVE THIS TOKEN")
    print("=" * 70)
    print()
    print(token)
    print()
    print("=" * 70)
    print()

    print("Add it to your local/admin environment:")
    print()
    print(f"OPENBAO_TERRAFORM_TOKEN={token}")
    print()
    print("Do NOT commit this token to Git.")
    print()


if __name__ == "__main__":
    main()
