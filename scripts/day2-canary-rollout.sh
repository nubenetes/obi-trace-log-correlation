#!/usr/bin/env bash
# Day 2: Canary Progressive Rollout for OBI Trace-Log Correlation
# Dynamically adjusts OBI ConfigMap match rules to enable or rollback log enrichment per service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

ACTION="${1:-status}" # enable, disable, status
SERVICE_PATH="${2:-/backend}"

CONFIGMAP_NAME="obi-config"
NAMESPACE="obi"

usage() {
    echo "Usage: $0 [status | enable <exe_path> | disable <exe_path> | disable-all]"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 enable /frontend"
    echo "  $0 disable /frontend"
    echo "  $0 disable-all"
    exit 1
}

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_fatal "Kubernetes context or ConfigMap '$CONFIGMAP_NAME' in namespace '$NAMESPACE' not found."
fi

case "$ACTION" in
    status)
        log_info "Fetching current OBI trace-log annotation configuration..."
        kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data.obi-config\.yml}' | grep -A 15 "log_trace_annotation"
        ;;

    enable)
        log_info "Canary Rollout: Enabling trace-log correlation for service path '$SERVICE_PATH'..."
        TMP_CFG=$(mktemp)
        kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data.obi-config\.yml}' > "$TMP_CFG"
        if grep -q "$SERVICE_PATH" "$TMP_CFG"; then
            log_warn "Service path '$SERVICE_PATH' is already present in configuration."
        else
            # Append exe_path_glob under log_trace_annotation.match.process.exe_path_glob
            sed -i "/exe_path_glob:/a \                    - $SERVICE_PATH" "$TMP_CFG"
            kubectl create configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" --from-file=obi-config.yml="$TMP_CFG" --dry-run=client -o yaml | kubectl apply -f -
            log_success "Updated ConfigMap. Triggering OBI DaemonSet reload..."
            kubectl rollout restart ds/obi -n "$NAMESPACE"
            kubectl rollout status ds/obi -n "$NAMESPACE"
            log_success "Service '$SERVICE_PATH' successfully added to OBI trace-log annotation canary!"
        fi
        rm -f "$TMP_CFG"
        ;;

    disable)
        log_info "Canary Rollback: Disabling trace-log correlation for service path '$SERVICE_PATH'..."
        TMP_CFG=$(mktemp)
        kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data.obi-config\.yml}' > "$TMP_CFG"
        sed -i "\|- $SERVICE_PATH|d" "$TMP_CFG"
        kubectl create configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" --from-file=obi-config.yml="$TMP_CFG" --dry-run=client -o yaml | kubectl apply -f -
        kubectl rollout restart ds/obi -n "$NAMESPACE"
        kubectl rollout status ds/obi -n "$NAMESPACE"
        log_success "Service '$SERVICE_PATH' removed from OBI log annotation."
        rm -f "$TMP_CFG"
        ;;

    disable-all)
        log_info "Emergency Killswitch: Disabling trace-log annotation globally..."
        TMP_CFG=$(mktemp)
        kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data.obi-config\.yml}' > "$TMP_CFG"
        sed -i 's/enabled: true/enabled: false/g' "$TMP_CFG"
        kubectl create configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" --from-file=obi-config.yml="$TMP_CFG" --dry-run=client -o yaml | kubectl apply -f -
        kubectl rollout restart ds/obi -n "$NAMESPACE"
        kubectl rollout status ds/obi -n "$NAMESPACE"
        log_success "OBI log_trace_annotation globally disabled. Applications are completely unaffected."
        rm -f "$TMP_CFG"
        ;;

    *)
        usage
        ;;
esac
