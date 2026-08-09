#!/bin/bash
# deploy.sh — Phased Terraform deployment script
#
# Deploys the full infrastructure in the correct dependency order,
# stopping immediately on any error.
#
# Usage:
#   ./deploy.sh              # full deployment
#   ./deploy.sh --from 3     # resume from phase 3
#   ./deploy.sh --only 3     # run phase 3 only
#
# Prerequisites:
#   - terraform init already run
#   - terraform.tfvars populated
#   - OpenBao bootstrap completed (see OPENBAO_BOOTSTRAP.md)
#   - clouds.yaml configured for OpenStack provider

set -euo pipefail  # exit on error, undefined vars, pipe failures

# ============================================================
# Colours for output
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no colour

# ============================================================
# Helpers
# ============================================================
phase() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}Phase $1 — $2${NC}"
  echo -e "${BLUE}============================================================${NC}"
}

success() {
  echo -e "${GREEN}✓ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
  echo -e "${RED}✗ $1${NC}"
  exit 1
}

apply() {
  local description="$1"
  shift
  echo ""
  echo -e "${YELLOW}Applying: $description${NC}"
  terraform apply -auto-approve "$@" || error "Failed: $description"
  success "$description"
}

wait_for_input() {
  echo ""
  echo -e "${YELLOW}$1${NC}"
  read -r -p "Press ENTER when ready to continue..."
}

# ============================================================
# Argument parsing
# ============================================================
FROM_PHASE=1
ONLY_PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM_PHASE="$2"
      shift 2
      ;;
    --only)
      ONLY_PHASE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./deploy.sh [--from N] [--only N]"
      exit 1
      ;;
  esac
done

should_run() {
  local phase_num="$1"
  if [[ -n "$ONLY_PHASE" ]]; then
    [[ "$phase_num" == "$ONLY_PHASE" ]]
  else
    [[ "$phase_num" -ge "$FROM_PHASE" ]]
  fi
}

# ============================================================
# Phase 1 — Cluster
# ============================================================
if should_run 1; then
  phase 1 "Cluster"

  apply "Kubernetes cluster" \
    -target=infomaniak_kaas.cluster

  success "Phase 1 complete"
fi

# ============================================================
# Phase 2 — Node pools
# ============================================================
if should_run 2; then
  phase 2 "Node pools"

  apply "Management node pool" \
    -target=infomaniak_kaas_instance_pool.management

  apply "Worker node pool" \
    -target=infomaniak_kaas_instance_pool.workers

  success "Phase 2 complete"
fi

# ============================================================
# Phase 3 — Network + shared infrastructure
# ============================================================
if should_run 3; then
  phase 3 "Network + shared infrastructure"

  apply "OpenStack subnet lookup" \
    -target=data.openstack_networking_port_v2.worker \
    -target=data.openstack_identity_auth_scope_v3.current \
    -target=data.openstack_networking_subnet_v2.kaas

  apply "NGINX Ingress Controller" \
    -target=helm_release.nginx_ingress

  apply "cert-manager" \
    -target=helm_release.cert_manager \
    -target=kubernetes_secret.cloudflare_api_token
  
  apply "Let's Encrypt ClusterIssuer" \
    -target=kubectl_manifest.letsencrypt_issuer

  success "Phase 3 complete"
fi

# ============================================================
# Phase 4 — OpenBao
# ============================================================
if should_run 4; then
  phase 4 "OpenBao"

  apply "OpenBao deployment" \
    -target=helm_release.openbao \
    -target=kubernetes_ingress_v1.openbao \
    -target=cloudflare_record.openbao

  warn "OpenBao deployed. Manual steps required before Phase 6:"
  echo ""
  echo "  1. Initialize OpenBao:"
  echo "     kubectl exec -n openbao openbao-0 -- bao operator init"
  echo ""
  echo "  2. Save the 5 unseal keys and root token securely"
  echo ""
  echo "  3. Unseal OpenBao (3 of 5 keys):"
  echo "     kubectl exec -n openbao openbao-0 -- bao operator unseal <key-1>"
  echo "     kubectl exec -n openbao openbao-0 -- bao operator unseal <key-2>"
  echo "     kubectl exec -n openbao openbao-0 -- bao operator unseal <key-3>"
  echo ""
  echo "  4. Follow README.md to create the Terraform policy and token"
  echo ""
  echo "  5. Add openbao_terraform_token to terraform.tfvars"

  wait_for_input "Complete the manual OpenBao bootstrap steps above then press ENTER"

  success "Phase 4 complete"
fi

# ============================================================
# Phase 5 — OpenBao configuration
# ============================================================
if should_run 5; then
  phase 5 "OpenBao configuration"

  apply "KV secrets engine" \
    -target=vault_mount.kv

  apply "Kubernetes auth backend" \
    -target=vault_auth_backend.kubernetes \
    -target=vault_kubernetes_auth_backend_config.kubernetes

  apply "Platform policies and roles" \
    -target=vault_policy.argocd \
    -target=vault_kubernetes_auth_backend_role.argocd

  success "Phase 5 complete"
fi

# ============================================================
# Phase 6 — Argo CD
# ============================================================
if should_run 6; then
  phase 6 "Argo CD"

  apply "Argo CD" \
    -target=helm_release.argocd \
    -target=kubernetes_ingress_v1.argocd \
    -target=cloudflare_record.argocd

  apply "Cloudflare Access argocd" \
    -target=cloudflare_zero_trust_access_application.argocd
  success "Phase 6 complete"
fi

# ============================================================
# Phase 7 — Argo CD app-of-apps bootstrap
# ============================================================
if should_run 7; then
  phase 7 "Argo CD app-of-apps bootstrap"

  warn "Before continuing, ensure:"
  echo ""
  echo "  1. GitHub App credentials stored in OpenBao UI at:"
  echo "     secret/platform/argocd-github-app"
  echo ""
  echo "  2. Argo CD repo server restarted to pick up credentials:"
  echo "     kubectl rollout restart deployment/argocd-repo-server -n argocd"
  echo ""
  echo "  3. Argo CD UI shows the GitHub organisation repository as connected"

  wait_for_input "Complete the GitHub App setup above then press ENTER"

  apply "Argo CD app-of-apps" \
    -target=kubectl_manifest.app_of_apps

  success "Phase 7 complete"
fi

# ============================================================
# Final — apply remaining resources
# ============================================================
if should_run 8; then
  phase 8 "Final apply — remaining resources"

  apply "All remaining resources" # no -target — applies everything left

  success "Phase 8 complete"
fi

# ============================================================
# Done
# ============================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Argo CD:  https://argocd.${TF_VAR_domain:-your-domain.com}"
echo "  OpenBao:  https://openbao.${TF_VAR_domain:-your-domain.com}"
echo ""
echo "Next steps:"
echo "  - Add application secrets in OpenBao UI"
echo "  - Push application manifests to applications-repo/applications/"
echo "  - Argo CD will automatically sync all registered applications"