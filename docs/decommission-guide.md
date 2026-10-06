# Decommission & Teardown Guide

When decommissioning OpenTelemetry eBPF Instrumentation (OBI) or removing trace-log correlation from a cluster, follow this orderly teardown procedure to ensure no orphaned kernel maps or log pipeline disruptions remain.

---

## 1. Automated Decommission

The fastest and safest approach is to run the automated decommission script:

```bash
# Clean up Kubernetes cluster resources
./scripts/decommission.sh k8s

# Clean up Docker Compose resources
./scripts/decommission.sh docker-compose
```

---

## 2. Manual Step-by-Step Teardown

### Step 1: Drain & Delete Demo Applications
Delete test applications first so no new write calls are intercepted:
```bash
kubectl delete namespace demo-apps --timeout=60s
```

### Step 2: Delete OBI DaemonSet
Deleting the DaemonSet terminates user-space reader processes and prompts OBI to detach its kprobes and uprobes:
```bash
kubectl delete daemonset obi -n obi --timeout=60s
```

### Step 3: Unpin Kernel BPF Maps
eBPF maps pinned under `/sys/fs/bpf/otel/` persist in kernel memory until explicitly unpinned or unmounted.
Run a one-shot cleaner pod or host command to remove the pinned map directory:
```bash
kubectl run obi-bpf-cleaner --rm -i --restart=Never \
    --image=alpine:3.20 \
    --privileged \
    --overrides='{
        "spec": {
            "hostPID": true,
            "containers": [{
                "name": "cleaner",
                "image": "alpine:3.20",
                "command": ["sh", "-c", "rm -rf /sys/fs/bpf/otel 2>/dev/null || true"],
                "securityContext": {"privileged": true},
                "volumeMounts": [{"name": "bpffs", "mountPath": "/sys/fs/bpf"}]
            }],
            "volumes": [{"name": "bpffs", "hostPath": {"path": "/sys/fs/bpf"}}]
        }
    }' -n obi
```

### Step 4: Remove RBAC and Namespace
```bash
kubectl delete namespace obi --timeout=60s
kubectl delete clusterrolebinding obi-agent-binding --ignore-not-found=true
kubectl delete clusterrole obi-agent-role --ignore-not-found=true
```

### Step 5: (OpenShift Only) Remove Custom SCC
```bash
oc delete scc obi-ebpf-scc --ignore-not-found=true
```

### Step 6: Log Forwarder Clean-Up
Once OBI is removed, application containers will no longer generate suppressed NUL placeholder lines.
You can safely remove the `body matches "^[\x00\s]*$"` filter from your log forwarders, though keeping it has negligible performance impact and prevents blank line ingestion.
