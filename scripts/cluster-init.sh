#!/usr/bin/env bash
# ==============================================================================
# Script: cluster-init.sh
# Description: Idempotent Kubernetes Cluster Bootstrap Automation
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Formatting and Logging
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ------------------------------------------------------------------------------
# Configuration & Constants
# ------------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-false}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-33.0.0}"

run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# Preflight Checks
# ------------------------------------------------------------------------------
preflight_checks() {
    log_info "Running preflight dependency checks..."

    for bin in kubectl helm; do
        if ! command -v "${bin}" &>/dev/null; then
            log_error "Missing required executable: ${bin}. Please install it to continue."
            exit 1
        fi
    done

    log_info "Verifying Kubernetes cluster connectivity..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Unable to connect to Kubernetes cluster. Ensure your KUBECONFIG is properly configured."
        exit 1
    fi

    log_success "Preflight checks passed."
}

# ------------------------------------------------------------------------------
# Step 1: Base Namespaces and Network Security Policies
# ------------------------------------------------------------------------------
bootstrap_base_cluster() {
    log_info "Applying base production namespace configuration..."
    run_cmd kubectl apply -f "${REPO_ROOT}/clusters/base/namespace.yaml"

    log_info "Enforcing default zero-trust network policies..."
    run_cmd kubectl apply -f "${REPO_ROOT}/clusters/base/network-policies.yaml"

    log_success "Base cluster primitives configured."
}

# ------------------------------------------------------------------------------
# Step 2: cert-manager Installation & ClusterIssuer
# ------------------------------------------------------------------------------
bootstrap_cert_manager() {
    log_info "Configuring Jetstack Helm repository for cert-manager..."
    run_cmd helm repo add jetstack https://charts.jetstack.io --force-update
    run_cmd helm repo update jetstack

    log_info "Deploying cert-manager (${CERT_MANAGER_VERSION}) into 'cert-manager' namespace..."
    run_cmd helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version "${CERT_MANAGER_VERSION}" \
        --set crds.enabled=true \
        --wait

    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for cert-manager webhook to become available..."
        kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s
    fi

    log_info "Applying production ClusterIssuer..."
    run_cmd kubectl apply -f "${REPO_ROOT}/infrastructure/cert-manager/cluster-issuer.yaml"

    log_success "cert-manager bootstrap complete."
}

# ------------------------------------------------------------------------------
# Step 3: Traefik Ingress Controller Deployment
# ------------------------------------------------------------------------------
bootstrap_traefik() {
    log_info "Configuring Traefik Helm repository..."
    run_cmd helm repo add traefik https://helm.traefik.io/traefik --force-update
    run_cmd helm repo update traefik

    log_info "Deploying Traefik Ingress Controller into 'traefik' namespace..."
    run_cmd helm upgrade --install traefik traefik/traefik \
        --namespace traefik \
        --create-namespace \
        --version "${TRAEFIK_CHART_VERSION}" \
        --values "${REPO_ROOT}/infrastructure/traefik/values.yaml" \
        --wait

    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for Traefik deployment rollout..."
        kubectl rollout status deployment/traefik -n traefik --timeout=120s
    fi

    log_success "Traefik Ingress Controller deployment complete."
}

# ------------------------------------------------------------------------------
# Summary & Next Steps
# ------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}================================================================${NC}"
    echo -e "${BOLD}${GREEN} Cluster Initialization Completed Successfully!                 ${NC}"
    echo -e "${BOLD}${GREEN}================================================================${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Verify Traefik LoadBalancer IP: ${BLUE}kubectl get svc -n traefik${NC}"
    echo -e "  2. Test sample IngressRoute:       ${BLUE}kubectl apply -f infrastructure/traefik/ingress-route.yaml${NC}"
    echo -e "  3. Validate ClusterIssuer status:  ${BLUE}kubectl get clusterissuers${NC}"
    echo ""
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    echo -e "${BOLD}Starting Kubernetes Platform Bootstrap Toolkit...${NC}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY_RUN mode enabled. No changes will be applied to the cluster."
    fi

    preflight_checks
    bootstrap_base_cluster
    bootstrap_cert_manager
    bootstrap_traefik
    print_summary
}

main "$@"
