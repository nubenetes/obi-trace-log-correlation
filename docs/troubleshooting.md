# Troubleshooting & Diagnostic Runbook

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [📈 Grafana & K8s](grafana-and-k8s-observability.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


This runbook covers common issues encountered when deploying and operating OBI trace-log correlation.

---

## 1. Trace Context Not Appearing in Logs

### Symptom
Application logs are written to stdout, but `trace_id` and `span_id` are absent.

### Diagnostics
1. **Is the workload matched in OBI configuration?**
   Inspect `obi-config.yml`:
   ```yaml
   extensions:
     obi:
       correlation:
         log_trace_annotation:
           enabled: true
           match:
             - process:
                 exe_path_glob:
                   - /frontend
   ```
   *Rule*: A process must be included in **both** `capture.rules` AND `log_trace_annotation.match`.

2. **Is the log written during an active trace?**
   OBI only injects trace context when a request or operation is in-flight on that thread.
   - Logs written at service startup or in background timers pass through untouched.
   - Send active HTTP traffic: `curl http://localhost:8080/checkout`.

3. **Is stdout buffered?**
   - In Python, verify `PYTHONUNBUFFERED=1` is set in the container environment.
   - In .NET, ensure synchronous console output is active.

---

## 2. Blank Lines / NUL Characters Visible in Log Backend

### Symptom
Log dashboards (Loki, Elasticsearch, CloudWatch) show empty lines or strings containing `\u0000` / `\x00`.

### Solution
The log shipping pipeline is missing the drop filter. OBI zeroes out original user buffers before re-emitting enriched lines.
Update your log shipper with the regex filter:
```regex
^[\x00\s]*$
```
See the [Log Shipper Filtering Guide](log-filtering-guide.md) for full configuration blocks.

---

## 3. Large Log Writes Splitting (> 8 KiB)

### Symptom
A long stack trace or JSON payload appears split across two log records, with only the first part enriched.

### Root Cause
OBI suppresses and enriches at most the first **8 KiB** of a single `write()` or `writev()` call.
Any bytes beyond 8 KiB pass through into the log stream un-enriched.

### Remediation
- Configure log formatters to truncate oversized payload dumps or stack frames to <= 8 KiB.
- Ship massive unstructured payloads to object storage (S3/GCS) and log only the reference URL.

---

## 4. Kernel Lockdown Denials

### Symptom
OBI pod fails to start with errors like:
```text
bpf_probe_write_user: Operation not permitted
```

### Root Cause
The Linux kernel is running in Secure Boot Lockdown mode (`integrity` or `confidentiality`). Kernel lockdown blocks `bpf_probe_write_user` to prevent arbitrary memory overwrites.

### Diagnostic Command
```bash
cat /sys/kernel/security/lockdown
# Returns: [none] integrity confidentiality
```
If `[integrity]` or `[confidentiality]` is enclosed in brackets, lockdown is active.
Disable lockdown in host BIOS/GRUB or use standard cloud virtual machines without locked EFI secure boot policies.

---

## 5. OpenShift Permission Denied / SCC Issues

### Symptom
In OpenShift 4.20+, the OBI pod is rejected by the admission controller with `forbidden: not authorized by any SecurityContextConstraints`.

### Remediation
Bind the dedicated `obi-ebpf-scc` to the ServiceAccount:
```bash
oc adm policy add-scc-to-user obi-ebpf-scc -z obi-agent -n obi
```
Or allow the built-in `privileged` SCC:
```bash
oc adm policy add-scc-to-user privileged -z obi-agent -n obi
```


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Grafana & Kubernetes Observability**](grafana-and-k8s-observability.md) | [**Repository Overview**](../README.md) | [**Decommission & Teardown Guide**](decommission-guide.md) |

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
- 🔧 **[Troubleshooting & Diagnostics](troubleshooting.md)** — Common pitfalls, eBPF probe errors, missing trace IDs, and verification steps
- 🧹 **[Decommission & Teardown Guide](decommission-guide.md)** — Safe probe detachment, BPF map unpinning, and resource cleanup
- 📚 **[References & Official Documentation](references.md)** — Upstream OpenTelemetry specifications, GitHub repositories, and CNCF channels
