# Day 0: Planning, Prerequisites & Sizing Guide

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


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


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Architecture Deep Dive**](architecture.md) | [**Repository Overview**](../README.md) | [**Day 1: Multi-Cluster Deployment**](day1-installation.md) |

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
- 📊 **[OBI vs. Modern Observability Tools](obi-vs-modern-observability-tools.md)** — Architectural analysis & strategic conclusions comparing OBI against Datadog, Grafana, Dynatrace & New Relic
- 🔧 **[Troubleshooting & Diagnostics](troubleshooting.md)** — Common pitfalls, eBPF probe errors, missing trace IDs, and verification steps
- 🧹 **[Decommission & Teardown Guide](decommission-guide.md)** — Safe probe detachment, BPF map unpinning, and resource cleanup
- 📚 **[References & Official Documentation](references.md)** — Upstream OpenTelemetry specifications, GitHub repositories, and CNCF channels
