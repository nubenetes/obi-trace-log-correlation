# Day 0: Planning, Prerequisites & Sizing Guide

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [📈 Grafana & K8s](grafana-and-k8s-observability.md) &nbsp;|&nbsp; [📊 Metrics & Telemetry](ebpf-metrics-and-telemetry.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

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

### Cluster Scale Sizing Reference Matrix

| Fleet Scale | Worker Nodes | Active Pods | Avg Request Volume | Total BPF Map Memory | Total DaemonSet RAM | Recommended DaemonSet CPU Limit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Small / Dev** | 5 – 10 nodes | 50 – 200 | ~1,000 req/sec | ~180 MiB cluster-wide | 2.5 GiB – 5.0 GiB total | `100m` per node |
| **Medium / Staging**| 25 – 50 nodes | 500 – 1,500 | ~10,000 req/sec | ~900 MiB cluster-wide | 12.5 GiB – 25 GiB total | `200m` per node |
| **Large / Production**| 100 – 250 nodes | 2,500 – 7,500| ~50,000 req/sec | ~4.5 GiB cluster-wide | 50 GiB – 125 GiB total | `400m` per node |
| **Enterprise Hyperscale**| 500+ nodes | 15,000+ | 150,000+ req/sec | ~9.0 GiB cluster-wide | 250+ GiB total | `500m` per node |

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

### Kernel Lockdown LSM & Secure Boot Policies

The Linux kernel contains a security module (LSM) known as **Kernel Lockdown**, designed to prevent user-space processes (even with `root` / `CAP_SYS_ADMIN`) from modifying running kernel code and user-space memory:

- **Modes**:
  - `[none]`: Lockdown disabled. Full eBPF capability enabled, including `bpf_probe_write_user`. (**Required for OBI**).
  - `[integrity]`: Prevents user-space modification of running kernel memory. Blocks `bpf_probe_write_user` system calls (`EPERM`).
  - `[confidentiality]`: Prevents user-space inspection of confidential kernel data. Blocks memory probing and tracing.
- **Verification Command**:
  ```bash
  cat /sys/kernel/security/lockdown
  # Healthy output: [none] integrity confidentiality
  ```
- **Remediation**:
  If lockdown is enforced by UEFI Secure Boot, pass `lockdown=none` as a kernel boot parameter in GRUB or provision node groups without locked EFI secure boot enforcement (standard in AWS AL2023, Azure Linux, and RHCOS).

### SELinux & AppArmor Postures

In hardened distributions (RHEL, RHCOS, Ubuntu CIS, SLES):
1. **SELinux (OpenShift / RHEL)**:
   - In container runtimes, processes running with `spc_t` (Super Privileged Container) can access `/sys/fs/bpf` and mount bpffs.
   - The provided `obi-ebpf-scc` binds the DaemonSet to the privileged SELinux domain automatically.
2. **AppArmor (Ubuntu / Debian / SUSE)**:
   - Modern AppArmor profiles restrict mounting bpffs and attaching tracepoints.
   - Annotate the DaemonSet pod template to run unconfined:
     ```yaml
     metadata:
       annotations:
         container.apparmor.security.beta.kubernetes.io/obi: "unconfined"
     ```


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
- 📈 **[Grafana & Kubernetes Observability Guide](grafana-and-k8s-observability.md)** — Grafana dashboard integration (OSS, Cloud, Enterprise) and zero-Grafana full observability on OpenShift, AKS, EKS, GKE & RKE2
- 📊 **[Metrics & Telemetry Architecture Guide](ebpf-metrics-and-telemetry.md)** — Zero-code application RED metrics, Prometheus Exemplars, and kernel health monitoring
- 🔧 **[Troubleshooting & Diagnostics](troubleshooting.md)** — Common pitfalls, eBPF probe errors, missing trace IDs, and verification steps
- 🧹 **[Decommission & Teardown Guide](decommission-guide.md)** — Safe probe detachment, BPF map unpinning, and resource cleanup
- 📚 **[References & Official Documentation](references.md)** — Upstream OpenTelemetry specifications, GitHub repositories, and CNCF channels
