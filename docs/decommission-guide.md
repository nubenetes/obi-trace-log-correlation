# Decommission & Teardown Guide

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


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


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Troubleshooting & Diagnostics**](troubleshooting.md) | [**Repository Overview**](../README.md) | [**References & Official Documentation**](references.md) |

### 📚 Complete Guide Catalog
- 📜 **[Official Reference Announcement](reference-blog-announcement.md)** — Verbatim OpenTelemetry announcement with junior primers and kernel deep dives
- 🏛️ **[Architecture Deep Dive](architecture.md)** — Low-level syscall hooks (`pipe_write`, `ksys_write`, `do_writev`), LRU maps, and ringbuffer flow
- 📋 **[Day 0: Planning & Sizing](day0-planning-sizing.md)** — Linux 6.0+ matrix, kernel lockdown, memory sizing formulas, and security postures
- 📦 **[Day 1: Multi-Cluster Deployment](day1-installation.md)** — Enterprise overlays for OpenShift 4.20+, AKS, EKS, GKE, RKE2, and Docker Compose
- 🚨 **[Day 2: Operations & Incident Triage](day2-operations-triage.md)** — SRE incident response playbook, LogQL/Jaeger queries, and canary rollouts
- 💧 **[Log Shipper Filtering Guide](log-filtering-guide.md)** — Suppressed NUL byte placeholder drop filters and 8 KiB write split handling
- ⚡ **[Runtime Compatibility Guide](runtime-compatibility.md)** — Go runtime hooks, `PYTHONUNBUFFERED=1`, Node.js async streams, and Java Loom
- 🌐 **[Frontend SPAs & SSR Telemetry Guide](frontend-spa-ssr-telemetry.md)** — W3C `traceparent` HTTP bridge, Angular/React/Vue patterns, and SSR kernel interception
- 🕸️ **[Service Mesh vs. eBPF Observability Guide](service-mesh-vs-ebpf-observability.md)** — Architectural comparison between Istio Ambient (ztunnel/waypoint) network proxying and OBI kernel-level trace-log enrichment
- 🔧 **[Troubleshooting & Diagnostics](troubleshooting.md)** — Common pitfalls, eBPF probe errors, missing trace IDs, and verification steps
- 🧹 **[Decommission & Teardown Guide](decommission-guide.md)** — Safe probe detachment, BPF map unpinning, and resource cleanup
- 📚 **[References & Official Documentation](references.md)** — Upstream OpenTelemetry specifications, GitHub repositories, and CNCF channels
