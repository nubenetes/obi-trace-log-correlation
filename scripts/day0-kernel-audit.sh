#!/usr/bin/env bash
# Day 0: Preflight Kernel & Environment Audit for OBI Trace-Log Correlation
# Checks kernel version, BPF filesystem, lockdown status, and node compatibility.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "======================================================================"
echo "  OBI Trace-Log Correlation: Day 0 Preflight Audit"
echo "======================================================================"

AUDIT_FAILED=0

# 1. Host Architecture Check
ARCH=$(uname -m)
log_info "Host Architecture: $ARCH"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    log_fatal "Unsupported architecture: $ARCH. OBI supports x86_64 and arm64/aarch64."
fi
log_success "Architecture supported."

# 2. Host Kernel Version Check
KERNEL_RELEASE=$(uname -r)
log_info "Host Kernel Release: $KERNEL_RELEASE"

# Parse major.minor version
KERNEL_MAJOR=$(echo "$KERNEL_RELEASE" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_RELEASE" | cut -d. -f2)

if (( KERNEL_MAJOR > 6 )) || (( KERNEL_MAJOR == 6 && KERNEL_MINOR >= 0 )); then
    log_success "Kernel version >= 6.0 detected (Linux $KERNEL_MAJOR.$KERNEL_MINOR). Full write() [ITER_UBUF] and writev() [ITER_IOVEC] log enrichment supported!"
else
    log_warn "Kernel is older than 6.0 (Linux $KERNEL_MAJOR.$KERNEL_MINOR). Only writev()-based log enrichment will function; write() calls will pass un-enriched."
fi

# 3. Check BPF Filesystem Mount (/sys/fs/bpf)
log_info "Checking BPF filesystem mount at /sys/fs/bpf..."
if mount | grep -q "type bpf"; then
    log_success "/sys/fs/bpf is mounted as bpffs."
else
    log_warn "/sys/fs/bpf is NOT mounted. To mount: sudo mount -t bpf bpffs /sys/fs/bpf"
fi

# 4. Kernel Lockdown Mode Check
log_info "Checking Kernel Lockdown mode..."
if [[ -f /sys/kernel/security/lockdown ]]; then
    LOCKDOWN_STATUS=$(cat /sys/kernel/security/lockdown 2>/dev/null || echo "unknown")
    log_info "Lockdown status: $LOCKDOWN_STATUS"
    if echo "$LOCKDOWN_STATUS" | grep -q "\[none\]"; then
        log_success "Kernel is NOT locked down. eBPF probes can attach."
    else
        log_error "Kernel is locked down! eBPF kprobes and bpf_probe_write_user will fail."
        AUDIT_FAILED=1
    fi
else
    log_info "Kernel security lockdown file not present (typical on non-EFI or standard distros)."
    log_success "Kernel lockdown inactive."
fi

# 5. BPF JIT Compiler Check
if [[ -f /proc/sys/net/core/bpf_jit_enable ]]; then
    JIT_ENABLED=$(cat /proc/sys/net/core/bpf_jit_enable)
    if [[ "$JIT_ENABLED" == "1" || "$JIT_ENABLED" == "2" ]]; then
        log_success "BPF JIT compiler is enabled (bpf_jit_enable=$JIT_ENABLED)."
    else
        log_warn "BPF JIT compiler is disabled ($JIT_ENABLED). Enable via: sudo sysctl -w net.core.bpf_jit_enable=1"
    fi
fi

# 6. Kubernetes Cluster Nodes Audit (if kubectl is connected)
if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    echo "----------------------------------------------------------------------"
    log_info "Auditing Kubernetes Cluster Nodes..."
    echo "----------------------------------------------------------------------"
    printf "%-30s %-25s %-20s\n" "NODE NAME" "OS IMAGE" "KERNEL VERSION"
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.osImage}{"\t"}{.status.nodeInfo.kernelVersion}{"\n"}{end}' | while IFS=$'\t' read -r node os kern; do
        printf "%-30s %-25s %-20s\n" "$node" "$os" "$kern"
        NODE_MAJOR=$(echo "$kern" | cut -d. -f1)
        if (( NODE_MAJOR < 6 )); then
            log_warn "Node '$node' runs kernel $kern (< 6.0). Recommend upgrading to RHCOS 9 / AL2023 / Ubuntu 24.04."
        fi
    done
    log_success "Kubernetes node audit complete."
fi

echo "======================================================================"
if (( AUDIT_FAILED == 0 )); then
    log_success "Day 0 Preflight Audit PASSED! Environment is ready for OBI rollout."
else
    log_fatal "Day 0 Preflight Audit FAILED! Address the errors above before proceeding."
fi
