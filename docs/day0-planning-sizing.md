# Day 0: Planning, Prerequisites & Sizing Guide

## 1. Prerequisites Checklist

Before rolling out OpenTelemetry eBPF Instrumentation (OBI) with trace-log correlation across your Kubernetes clusters, verify the following prerequisites:

| Item | Requirement | Verification Command |
|---|---|---|
| **Operating System** | Linux 64-bit (`x86_64` or `arm64`) | `uname -m` |
| **Linux Kernel** | >= 6.0 (for full `write()` & `writev()` log enrichment) | `uname -r` |
| **BPF Filesystem** | Mounted at `/sys/fs/bpf` | `mount \| grep bpffs` |
| **Kernel Lockdown** | Inactive (`[none]`) | `cat /sys/kernel/security/lockdown` |
| **BPF JIT Compiler** | Enabled (`1` or `2`) | `cat /proc/sys/net/core/bpf_jit_enable` |
| **Privileges** | Root / `CAP_SYS_ADMIN` in DaemonSet | Checked via Pod Security Admission / SCC |

---

## 2. Cluster Compatibility Matrix

| Distribution | Default Node OS | Kernel Version | OBI Trace-Log Status |
|---|---|---|---|
| **OpenShift 4.20+** | Red Hat Enterprise Linux CoreOS (RHCOS) | Linux 6.6+ / 6.12+ | **Fully Supported** (requires custom SCC) |
| **Azure AKS** | Azure Linux 3.0 / Ubuntu 24.04 | Linux 6.6+ / 6.8+ | **Fully Supported** |
| **AWS EKS** | Amazon Linux 2023 (AL2023) / Bottlerocket | Linux 6.1+ | **Fully Supported** (avoid legacy AL2) |
| **Google GKE** | Container-Optimized OS (COS) / Ubuntu | Linux 6.1+ / 6.6+ | **Fully Supported** (Standard mode required) |
| **Rancher RKE2** | Enterprise Linux 9 / SLES 15 SP5+ | Linux 6.x | **Fully Supported** |

---

## 3. Sizing & Capacity Planning

eBPF programs and maps utilize non-swappable kernel memory. Understanding memory allocations prevents unexpected Out-Of-Memory (OOM) events:

### BPF Map Allocations
- **`traces_ctx_v1` Map**: Preallocated kernel `LRU_HASH` map holding `u64 pid_tgid` keys and `obi_ctx_info_t` values.
  - Default entries: 10,000 threads.
  - Kernel memory: ~2.5 MB.
- **`log_events` Ring Buffer**: Preallocated per-node ring buffer for passing log events to user space.
  - Default size: 4 MB - 16 MB.

### User-Space OBI Agent Footprint
- **CPU**:
  - Idle / Baseline: < 15m CPU.
  - Under 10,000 req/sec: 80m – 150m CPU.
- **Memory**:
  - Request: `128Mi`
  - Limit: `512Mi`

### Overhead Formula
$$\text{Total Memory per Node} = \text{BPF Preallocated Maps (18 MiB)} + \text{Agent Memory (128-512 MiB)}$$

Latency overhead added to standard application requests: **< 0.15 ms (p99)**.

---

## 4. Security Architecture

1. **Pod Security Standards (PSS)**:
   The `obi` namespace requires `privileged` enforcement:
   ```yaml
   metadata:
     labels:
       pod-security.kubernetes.io/enforce: privileged
   ```
2. **OpenShift SecurityContextConstraints (SCC)**:
   In OpenShift, default projects are bound to `restricted-v2`. Deploy the provided `obi-ebpf-scc` which allows `hostPID` and `CAP_SYS_ADMIN`.
3. **Application Namespaces**:
   Demo and business application namespaces remain strictly hardened under `restricted` or `baseline` security standards. The application containers themselves require **zero elevated privileges**.
