# Log Shipper Filtering Guide: Dropping Suppressed NUL Byte Placeholders

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


## 1. Why Suppressed Lines Contain NUL Bytes

When an application invokes `write()` or `writev()` on stdout or stderr, the Linux kernel prepares to transfer the user-space memory buffer to the container's standard output pipe.

To prevent the container runtime (CRI-O, containerd, Docker) from logging **two identical lines** (the original un-enriched line and the enriched line), OBI's kernel probe performs an in-memory suppression:

1. **Interception**: eBPF intercepts the write syscall before the bytes reach the pipe buffer.
2. **Buffering**: eBPF reads the user buffer into kernel memory and dispatches it to the user-space ring buffer.
3. **Suppression via `bpf_probe_write_user`**: The eBPF program calls the kernel helper `bpf_probe_write_user()` to overwrite the application's original user-space memory buffer with zeroes (`\0` / NUL bytes) terminated by `\n`.
4. **Re-Emission**: OBI's user-space daemon injects `trace_id` and `span_id` and writes the enriched line back to the file descriptor.

As a direct consequence, the raw container log file on disk (`/var/log/pods/*/*/*.log`) receives:
- One line consisting solely of NUL (`\x00`) characters terminated by `\n` (the suppressed placeholder).
- One enriched line containing the full log message with `trace_id` and `span_id`.

---

## 2. The 8 KiB Write Boundary

> [!WARNING]
> OBI enriches and suppresses at most the first **8 KiB** of a single `write()` or `writev()`.
> If an application writes a single log record exceeding 8 KiB:
> - The first 8 KiB is enriched and replaced with NUL bytes.
> - The remaining bytes pass through un-enriched into the log stream and **will not match** the placeholder filter.
> Always ensure application log formatters avoid emitting single monolithic writes larger than 8 KiB (e.g. huge stack traces with mega payloads).

---

## 3. Log Shipper Filter Configurations

Your log forwarding pipeline must filter out records that match `^[\x00\s]*$`. Below are drop configurations for all major enterprise log forwarders:

### A. OpenTelemetry Collector (`filelog` receiver)
```yaml
receivers:
  filelog:
    include:
      - /var/log/pods/*/*/*.log
    start_at: end
    operators:
      # Step 1: Parse container runtime log format (CRI / Docker)
      - type: container
        id: container-parser
      # Step 2: Drop placeholder lines filled with NUL characters
      - type: filter
        id: drop-obi-nul-placeholders
        expr: 'body matches "^[\\x00\\s]*$"'
```

### B. Vector (Vector Remap Language / Filter Transform)
```toml
[transforms.filter_obi_nul_placeholders]
type = "filter"
inputs = ["kubernetes_logs"]
condition = '!match(string!(.message), r"^[\x00\s]*$")'
```

### C. Fluent Bit
```ini
[FILTER]
    Name    grep
    Match   kube.*
    Exclude log ^[\x00\s]*$
```

### D. Promtail / Grafana Alloy
```yaml
scrape_configs:
  - job_name: kubernetes-pods
    pipeline_stages:
      - cri: {}
      - drop:
          expression: "^[\\x00\\s]*$"
```


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Day 2: Operations & Incident Triage**](day2-operations-triage.md) | [**Repository Overview**](../README.md) | [**Runtime Compatibility Guide**](runtime-compatibility.md) |

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
