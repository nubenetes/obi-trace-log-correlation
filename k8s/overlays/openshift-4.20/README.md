# OpenShift 4.20+ Deployment Guide: OBI Trace-Log Correlation

## 1. Overview & Kernel Compatibility
OpenShift 4.20+ runs Red Hat Enterprise Linux CoreOS (RHCOS) with Linux kernel 6.6+ or 6.12+.
This satisfies the OBI trace-log correlation requirement (`kernel >= 6.0`) for intercepting both `write()` (`ITER_UBUF`) and `writev()` (`ITER_IOVEC`) syscalls.

## 2. SecurityContextConstraints (SCC) & RBAC
In OpenShift, default projects enforce `restricted-v2` SCC, which prohibits:
- `hostPID: true`
- `privileged: true`
- HostPath mounts (`/sys/fs/bpf`, `/sys/kernel/debug`)

This overlay provisions a dedicated SCC (`obi-ebpf-scc`) and automatically binds it to `system:serviceaccount:obi:obi-agent`.

Alternatively, cluster administrators can grant the built-in `privileged` SCC:
```bash
oc adm policy add-scc-to-user privileged -z obi-agent -n obi
```

## 3. SELinux Configuration
OpenShift enforces SELinux in enforcing mode. The DaemonSet patch applies:
```yaml
securityContext:
  privileged: true
  seLinuxOptions:
    type: spc_t # Super Privileged Container type
```
This enables eBPF program attachment and `/sys/fs/bpf` map access without SELinux denials.

## 4. OpenShift Cluster Logging & LokiStack Integration
When OBI suppresses un-enriched log lines, the container runtime receives a line filled with NUL (`\x00`) bytes.
If using the Red Hat OpenShift Cluster Logging Operator (backed by Vector):
1. Ingest `vector-filter-configmap.yaml`.
2. Add the filter transform in your `ClusterLogForwarder` pipeline to ensure LokiStack does not index blank placeholder lines.

## 5. Deployment
```bash
# Verify cluster context
oc whoami

# Apply overlay via oc / kubectl kustomize
oc apply -k k8s/overlays/openshift-4.20

# Monitor DaemonSet rollout
oc rollout status ds/obi -n obi
```
