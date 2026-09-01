#!/usr/bin/env bash

set -a
source .env.platform
set +a

python3 create-app-token.py "$@"
