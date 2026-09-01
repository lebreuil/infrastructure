#!/usr/bin/env python3
"""
create-app-token.py — Create and verify an OpenBao application token.

This script uses the OpenBao HTTP API directly.

Flow:
    1. Verify the Terraform/admin token.
    2. Create an application token in the target namespace.
    3. Use the application token to write itself to OpenBao KV v2.
    4. Use the application token to read the secret back.

Requirements:
    pip install requests

Required environment variables:
    OPENBAO_ADDR
    OPENBAO_TERRAFORM_TOKEN
    BAO_NAMESPACE
    BAO_POLICY
    CF_ACCESS_CLIENT_ID
    CF_ACCESS_CLIENT_SECRET

Optional environment variables:
    TOKEN_TTL=720h
    SECRET_MOUNT=secret
    TOKEN_SECRET_PATH=bootstrap/app-token
"""

import os
import sys

import requests


# ============================================================
# Configuration
# ============================================================

OPENBAO_ADDR = os.environ.get("OPENBAO_ADDR", "").rstrip("/")
TERRAFORM_TOKEN = os.environ.get("OPENBAO_TERRAFORM_TOKEN", "")

BAO_NAMESPACE = os.environ.get("BAO_NAMESPACE", "")
BAO_POLICY = os.environ.get("BAO_POLICY", "")

TOKEN_TTL = os.environ.get("TOKEN_TTL", "720h")

SECRET_MOUNT = os.environ.get("SECRET_MOUNT", "secret")
TOKEN_SECRET_PATH = os.environ.get(
    "TOKEN_SECRET_PATH",
    "bootstrap/app-token",
)

CF_ACCESS_CLIENT_ID = os.environ.get(
    "CF_ACCESS_CLIENT_ID",
    "",
)

CF_ACCESS_CLIENT_SECRET = os.environ.get(
    "CF_ACCESS_CLIENT_SECRET",
    "",
)

DEBUG = os.environ.get("DEBUG", "").lower() in (
    "1",
    "true",
    "yes",
)


def api_request(method, path, token, namespace=None, **kwargs):
    """Perform an OpenBao API request and return JSON."""

    url = f"{OPENBAO_ADDR}/v1/{path.lstrip('/')}"

    headers = {
        "X-Vault-Token": token,
        "CF-Access-Client-Id": CF_ACCESS_CLIENT_ID,
        "CF-Access-Client-Secret": CF_ACCESS_CLIENT_SECRET,
    }

    if namespace:
        headers["X-Vault-Namespace"] = namespace

    # --------------------------------------------------------
    # Debug output
    #
    # Never print actual token or secret values.
    # --------------------------------------------------------

    if DEBUG:
        print()
        print(f"DEBUG: {method} {url}")
        print(
            "DEBUG: X-Vault-Token: "
            f"{'present' if token else 'MISSING'}"
        )
        print(
            "DEBUG: X-Vault-Namespace: "
            f"{namespace or '<root>'}"
        )
        print(
            "DEBUG: CF-Access-Client-Id: "
            f"{'present' if CF_ACCESS_CLIENT_ID else 'MISSING'}"
        )
        print(
            "DEBUG: CF-Access-Client-Secret: "
            f"{'present' if CF_ACCESS_CLIENT_SECRET else 'MISSING'}"
        )

        if "json" in kwargs:
            print(
                "DEBUG: Request JSON keys: "
                f"{list(kwargs['json'].keys())}"
            )

    try:
        response = requests.request(
            method=method,
            url=url,
            headers=headers,
            timeout=30,
            allow_redirects=False,
            **kwargs,
        )

    except requests.RequestException as exc:
        error(f"Cannot connect to OpenBao: {exc}")

    # --------------------------------------------------------
    # Debug response
    # --------------------------------------------------------

    if DEBUG:
        print(f"DEBUG: Response status: {response.status_code}")

        if response.is_redirect:
            print(
                "DEBUG: Redirect location: "
                f"{response.headers.get('Location', '<none>')}"
            )

        print(
            "DEBUG: Response content-type: "
            f"{response.headers.get('Content-Type', '<none>')}"
        )

    # Cloudflare Access redirect
    if 300 <= response.status_code < 400:
        error(
            "Request was redirected before reaching OpenBao.\n"
            f"HTTP {response.status_code}\n"
            f"Location: {response.headers.get('Location', '')}"
        )

    if not response.ok:
        try:
            details = response.json()
        except ValueError:
            details = response.text

        error(
            f"OpenBao API request failed:\n"
            f"  {method} /v1/{path}\n"
            f"  HTTP {response.status_code}: {details}"
        )

    if not response.content:
        return {}

    try:
        return response.json()
    except ValueError:
        return {}



# ============================================================
# Helpers
# ============================================================

def info(message):
    print(f"✓ {message}")


def error(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def require_environment():
    required = {
        "OPENBAO_ADDR": OPENBAO_ADDR,
        "OPENBAO_TERRAFORM_TOKEN": TERRAFORM_TOKEN,
        "BAO_NAMESPACE": BAO_NAMESPACE,
        "BAO_POLICY": BAO_POLICY,
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


def build_headers(token, namespace=None):
    headers = {
        "X-Vault-Token": token,
        "CF-Access-Client-Id": CF_ACCESS_CLIENT_ID,
        "CF-Access-Client-Secret": CF_ACCESS_CLIENT_SECRET,
    }

    if namespace:
        headers["X-Vault-Namespace"] = namespace

    return headers


def api_request(method, path, token, namespace=None, **kwargs):
    """Perform an OpenBao API request and return JSON."""

    url = f"{OPENBAO_ADDR}/v1/{path.lstrip('/')}"

    headers = {
        "X-Vault-Token": token,
        "CF-Access-Client-Id": CF_ACCESS_CLIENT_ID,
        "CF-Access-Client-Secret": CF_ACCESS_CLIENT_SECRET,
    }

    if namespace:
        headers["X-Vault-Namespace"] = namespace

    # --------------------------------------------------------
    # Debug output
    #
    # Never print actual token or secret values.
    # --------------------------------------------------------

    if DEBUG:
        print()
        print(f"DEBUG: {method} {url}")
        print(
            "DEBUG: X-Vault-Token: "
            f"{'present' if token else 'MISSING'}"
        )
        print(
            "DEBUG: X-Vault-Namespace: "
            f"{namespace or '<root>'}"
        )
        print(
            "DEBUG: CF-Access-Client-Id: "
            f"{'present' if CF_ACCESS_CLIENT_ID else 'MISSING'}"
        )
        print(
            "DEBUG: CF-Access-Client-Secret: "
            f"{'present' if CF_ACCESS_CLIENT_SECRET else 'MISSING'}"
        )

        if "json" in kwargs:
            print(
                "DEBUG: Request JSON keys: "
                f"{list(kwargs['json'].keys())}"
            )

    try:
        response = requests.request(
            method=method,
            url=url,
            headers=headers,
            timeout=30,
            allow_redirects=False,
            **kwargs,
        )

    except requests.RequestException as exc:
        error(f"Cannot connect to OpenBao: {exc}")

    # --------------------------------------------------------
    # Debug response
    # --------------------------------------------------------

    if DEBUG:
        print(f"DEBUG: Response status: {response.status_code}")

        if response.is_redirect:
            print(
                "DEBUG: Redirect location: "
                f"{response.headers.get('Location', '<none>')}"
            )

        print(
            "DEBUG: Response content-type: "
            f"{response.headers.get('Content-Type', '<none>')}"
        )

    # Cloudflare Access redirect
    if 300 <= response.status_code < 400:
        error(
            "Request was redirected before reaching OpenBao.\n"
            f"HTTP {response.status_code}\n"
            f"Location: {response.headers.get('Location', '')}"
        )

    if not response.ok:
        try:
            details = response.json()
        except ValueError:
            details = response.text

        error(
            f"OpenBao API request failed:\n"
            f"  {method} /v1/{path}\n"
            f"  HTTP {response.status_code}: {details}"
        )

    if not response.content:
        return {}

    try:
        return response.json()
    except ValueError:
        return {}


# ============================================================
# Main
# ============================================================

def main():
    require_environment()

    print()
    print("OpenBao application token creation")
    print("=" * 60)
    print(f"  OpenBao URL   : {OPENBAO_ADDR}")
    print(f"  Namespace     : {BAO_NAMESPACE}")
    print(f"  Policy        : {BAO_POLICY}")
    print(f"  Token TTL     : {TOKEN_TTL}")
    print(f"  Secret mount  : {SECRET_MOUNT}")
    print(f"  Secret path   : {TOKEN_SECRET_PATH}")
    print()

    # --------------------------------------------------------
    # 1. Verify the Terraform/admin token.
    #
    # This token is used without a namespace header because it
    # is the administrative token that manages child namespaces.
    # --------------------------------------------------------

    api_request(
        "GET",
        "auth/token/lookup-self",
        TERRAFORM_TOKEN,
    )

    info("Terraform/admin token authenticated")

    # --------------------------------------------------------
    # 1b. Verify the target policy actually exists in this
    #     namespace before using it. OpenBao will NOT error
    #     at token-create time if the policy name is wrong —
    #     it silently attaches zero capabilities instead.
    # --------------------------------------------------------

    try:
        api_request(
            "GET",
            f"sys/policies/acl/{BAO_POLICY}",
            TERRAFORM_TOKEN,
            namespace=BAO_NAMESPACE,
        )
    except SystemExit:
        error(
            f"Policy '{BAO_POLICY}' does not exist in namespace "
            f"'{BAO_NAMESPACE}'. Check for typos, whitespace, or "
            f"whether it was created in the wrong namespace."
        )

    info(f"Policy '{BAO_POLICY}' confirmed to exist in namespace '{BAO_NAMESPACE}'")

    # --------------------------------------------------------
    # 2. Create the application token in the target namespace.
    # --------------------------------------------------------

    response = api_request(
        "POST",
        "auth/token/create",
        TERRAFORM_TOKEN,
        namespace=BAO_NAMESPACE,
        json={
            "policies": [BAO_POLICY],
            "ttl": TOKEN_TTL,
            "renewable": True,
            "no_default_policy": True,
            "display_name": f"{BAO_NAMESPACE}-application",
        },
    )

    try:
        application_token = response["auth"]["client_token"]
    except (KeyError, TypeError):
        error("OpenBao did not return an application token")

    info(
        f"Application token created for namespace "
        f"'{BAO_NAMESPACE}'"
    )

    # --------------------------------------------------------
    # 2b. Diagnostic: verify what the application token can
    #     actually do, without ever printing the token itself.
    # --------------------------------------------------------

    lookup = api_request(
        "GET",
        "auth/token/lookup-self",
        application_token,
        namespace=BAO_NAMESPACE,
    )

    token_policies = lookup.get("data", {}).get("policies")
    token_namespace_path = lookup.get("data", {}).get("namespace_path")
    token_ttl = lookup.get("data", {}).get("ttl")

    info(f"Application token policies       : {token_policies}")
    info(f"Application token namespace_path : {token_namespace_path!r}")
    info(f"Application token ttl (seconds)  : {token_ttl}")

    if token_policies != [BAO_POLICY]:
        error(
            f"Expected policies == [{BAO_POLICY!r}], "
            f"but token actually has {token_policies!r}"
        )

    # --------------------------------------------------------
    # 3. Use the application token itself to write the token
    #    into KV v2.
    #
    # This proves that write access works.
    # --------------------------------------------------------

    secret_api_path = (
        f"{SECRET_MOUNT}/data/{TOKEN_SECRET_PATH}"
    )

    api_request(
        "POST",
        secret_api_path,
        application_token,
        namespace=BAO_NAMESPACE,
        json={
            "data": {
                "token": application_token,
            }
        },
    )

    info("Application token successfully wrote its bootstrap secret")

    # --------------------------------------------------------
    # 4. Use the application token to read the secret back.
    #
    # This proves that read access works.
    # --------------------------------------------------------

    stored = api_request(
        "GET",
        secret_api_path,
        application_token,
        namespace=BAO_NAMESPACE,
    )

    try:
        stored_token = stored["data"]["data"]["token"]
    except (KeyError, TypeError):
        error("Application token could not read its bootstrap secret")

    if stored_token != application_token:
        error(
            "Bootstrap secret was read successfully, "
            "but the stored token does not match"
        )

    info("Application token successfully read its bootstrap secret")

    # --------------------------------------------------------
    # Success
    # --------------------------------------------------------

    print()
    print("=" * 60)
    print("Application token successfully created and verified")
    print("=" * 60)
    print()

    print("Token stored at:")
    print(f"  Namespace : {BAO_NAMESPACE}")
    print(f"  Path      : {SECRET_MOUNT}/{TOKEN_SECRET_PATH}")
    print()


if __name__ == "__main__":
    main()
