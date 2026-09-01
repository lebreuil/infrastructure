#!/usr/bin/env bash

set -a
source .env.bootstrap
set +a

python3 openbao-bootstrap.py "$@"