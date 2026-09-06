#!/usr/bin/env bash

read -r -p "Application name: " app_name

if [[ -z "$app_name" ]]; then
  echo "Application name is required." >&2
  exit 1
fi

env_file=".env.${app_name}"

if [[ ! -f "$env_file" ]]; then
  echo "Environment file not found: $env_file" >&2
  exit 1
fi

set -a
source "$env_file"
set +a

python3 create-app-token.py "$@"
