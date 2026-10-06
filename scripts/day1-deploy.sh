#!/usr/bin/env bash
# Day 1: Automated Deployment Script for OBI Trace-Log Correlation
# Supports OpenShift 4.20+, AKS, EKS, GKE, RKE, and Docker Compose.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

CLUSTER_TYPE=""
DRY_RUN=false

usage() {
    echo "Usage: $0 --cluster <openshift|aks|eks|gke|rke|docker-compose> [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --cluster <type>   Target deployment environment:"
    echo "                     - openshift     : OpenShift 4.20+ with custom SCC & Vector filter"
    echo "                     - aks           : Azure Kubernetes Service (Azure Linux/Ubuntu)"
    echo "                     - eks           : AWS Elastic Kubernetes Service (AL2023/Bottlerocket)"
    echo "                     - gke           : Google Kubernetes Engine (Standard COS/Ubuntu)"
    echo "                     - rke           : Rancher RKE2 / K3s"
    echo "                     - docker-compose: Local Docker Compose test environment"
    echo "  --dry-run          Preview manifests without applying"
    echo "  -h, --help         Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cluster)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            ;;
    esac
done

if [[ -z "$CLUSTER_TYPE" ]]; then
    log_fatal "Missing required flag --cluster. Run with -h for help."
fi

log_info "Starting Day 1 Deployment for cluster target: ${BOLD}${CLUSTER_TYPE}${RESET}"

if [[ "$CLUSTER_TYPE" == "docker-compose" ]]; then
    COMPOSE_CMD=""
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        log_fatal "Neither 'docker compose' nor 'docker-compose' is available."
    fi

    COMPOSE_FILE="${ROOT_DIR}/docker-compose/compose.yaml"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Validating docker compose file..."
        $COMPOSE_CMD -f "$COMPOSE_FILE" config
        log_success "Docker Compose syntax valid."
        exit 0
    fi
    log_info "Building and launching containers via Docker Compose..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d --build
    log_success "Docker Compose stack is running!"
    echo "To view logs: $COMPOSE_CMD -f $COMPOSE_FILE logs -f"
    echo "To test: curl http://localhost:8080/checkout"
    exit 0
fi

# Kubernetes Deployment Paths
check_command kubectl

OVERLAY_DIR="${ROOT_DIR}/k8s/overlays/${CLUSTER_TYPE}"
if [[ ! -d "$OVERLAY_DIR" ]]; then
    log_fatal "Overlay directory does not exist: $OVERLAY_DIR"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Rendering Kustomize overlay for $CLUSTER_TYPE..."
    kubectl kustomize "$OVERLAY_DIR"
    log_success "Dry run rendering succeeded."
    exit 0
fi

log_info "Applying Kustomize overlay: $OVERLAY_DIR"
kubectl apply -k "$OVERLAY_DIR"

log_info "Waiting for OTel Collector rollout..."
kubectl rollout status deployment/otel-collector -n obi --timeout=120s || log_warn "OTel Collector rollout took longer than expected"

log_info "Waiting for OBI DaemonSet rollout..."
kubectl rollout status daemonset/obi -n obi --timeout=180s || log_warn "OBI DaemonSet rollout took longer than expected"

log_info "Waiting for Demo Services rollout..."
kubectl rollout status deployment/backend -n demo-apps --timeout=120s || true
kubectl rollout status deployment/frontend -n demo-apps --timeout=120s || true

log_success "Deployment completed successfully for ${CLUSTER_TYPE}!"
echo ""
echo "Next steps:"
echo "1. Generate traffic: ${SCRIPT_DIR}/day1-generate-traffic.sh"
echo "2. Verify correlation: ${SCRIPT_DIR}/day2-verify-correlation.sh"
