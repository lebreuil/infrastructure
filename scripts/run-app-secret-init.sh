#!/usr/bin/env bash

set -a
source .env.app
set +a

python3 app-secrets-init.py "$@"