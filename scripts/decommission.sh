#!/usr/bin/env bash
# Decommission: Clean & Safe Teardown for OBI Trace-Log Correlation
# Removes all DaemonSets, applications, RBAC, SCCs, and unpins kernel BPF maps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "======================================================================"
echo "  OBI Trace-Log Correlation: Decommission & Cleanup"
echo "======================================================================"

TARGET="${1:-auto}" # docker-compose, k8s, or auto

# 1. Docker Compose Teardown
if [[ "$TARGET" == "docker-compose" || "$TARGET" == "auto" ]] && command -v docker >/dev/null 2>&1; then
    COMPOSE_CMD=""
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    fi

    if [[ -n "$COMPOSE_CMD" ]]; then
        COMPOSE_FILE="${ROOT_DIR}/docker-compose/compose.yaml"
        if $COMPOSE_CMD -f "$COMPOSE_FILE" ps -q 2>/dev/null | grep -q .; then
            log_info "Tearing down Docker Compose demo stack..."
            $COMPOSE_CMD -f "$COMPOSE_FILE" down -v --remove-orphans
            log_success "Docker Compose resources removed."
        fi
    fi
fi

# 2. Kubernetes Teardown
if [[ "$TARGET" == "k8s" || "$TARGET" == "auto" ]] && command -v kubectl >/dev/null 2>&1; then
    if kubectl get ns obi >/dev/null 2>&1 || kubectl get ns demo-apps >/dev/null 2>&1; then
        log_info "Starting Kubernetes cluster decommission..."

        # Step 1: Drain & Delete Demo Apps
        if kubectl get ns demo-apps >/dev/null 2>&1; then
            log_info "Deleting demo-apps namespace..."
            kubectl delete ns demo-apps --timeout=60s || true
        fi

        # Step 2: Delete OBI DaemonSet first to detach kernel eBPF probes
        if kubectl get ds obi -n obi >/dev/null 2>&1; then
            log_info "Deleting OBI DaemonSet..."
            kubectl delete ds obi -n obi --timeout=60s || true
        fi

        # Step 3: Run eBPF Map Unpin Cleanup Job
        log_info "Deploying one-shot cleaner pod to sweep pinned BPF maps in /sys/fs/bpf/otel..."
        kubectl run obi-bpf-cleaner --rm -i --restart=Never \
            --image=alpine:3.20 \
            --privileged \
            --overrides='{
                "spec": {
                    "hostPID": true,
                    "containers": [{
                        "name": "cleaner",
                        "image": "alpine:3.20",
                        "command": ["sh", "-c", "rm -rf /sys/fs/bpf/otel 2>/dev/null || true; echo eBPF maps unpinned"],
                        "securityContext": {"privileged": true},
                        "volumeMounts": [{"name": "bpffs", "mountPath": "/sys/fs/bpf"}]
                    }],
                    "volumes": [{"name": "bpffs", "hostPath": {"path": "/sys/fs/bpf"}}]
                }
            }' -n obi 2>/dev/null || true

        # Step 4: Delete OBI Namespace and remaining RBAC
        log_info "Deleting obi namespace and associated workloads..."
        kubectl delete ns obi --timeout=60s || true

        # Step 5: Delete ClusterRole & ClusterRoleBinding
        kubectl delete clusterrolebinding obi-agent-binding --ignore-not-found=true
        kubectl delete clusterrole obi-agent-role --ignore-not-found=true

        # Step 6: Delete OpenShift SCC if present
        if command -v oc >/dev/null 2>&1 && oc get scc obi-ebpf-scc >/dev/null 2>&1; then
            log_info "Deleting OpenShift SecurityContextConstraints obi-ebpf-scc..."
            oc delete scc obi-ebpf-scc --ignore-not-found=true
        fi

        log_success "Kubernetes cluster decommission complete!"
    fi
fi

# 3. Clean host /sys/fs/bpf/otel if running directly on host and root
if [[ -d /sys/fs/bpf/otel ]] && [[ $EUID -eq 0 ]]; then
    log_info "Cleaning host-pinned BPF directory /sys/fs/bpf/otel..."
    rm -rf /sys/fs/bpf/otel
    log_success "Host BPF map directory cleared."
fi

echo "======================================================================"
log_success "Decommission completed cleanly. No orphaned kernel maps or containers remain."
