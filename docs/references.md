# References & Official Documentation

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [📈 Grafana & K8s](grafana-and-k8s-observability.md) &nbsp;|&nbsp; [📊 Metrics & Telemetry](ebpf-metrics-and-telemetry.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


This reference guide catalogs all official OpenTelemetry documentation, blog posts, repositories, and community resources related to **OpenTelemetry eBPF Instrumentation (OBI)** and zero-code trace-log correlation.

---

## 1. Official Announcements & Articles
- **Local Unabridged Reference & Analysis**: [docs/reference-blog-announcement.md](reference-blog-announcement.md)
  - Contains the complete, verbatim text of the official announcement plus junior primers and advanced kernel deep dives.
- **OpenTelemetry Blog Post**: [Zero-code trace-log correlation with OBI](https://opentelemetry.io/blog/2026/obi-trace-log-correlation/)
  - *Summary*: Primary announcement detailing the motivation, kernel interception mechanism, JSON/plain-text formatting, and rollout guidance.
- **Markdown Version of Blog Post**: [https://opentelemetry.io/blog/2026/obi-trace-log-correlation/index.md](https://opentelemetry.io/blog/2026/obi-trace-log-correlation/index.md)

---

## 2. Technical Documentation
- **Official OBI Trace-Log Documentation**: [Trace-log correlation Guide](https://opentelemetry.io/docs/zero-code/obi/trace-log-correlation/)
  - *Summary*: Configuration specs for Config v1 and Config v2, runtime buffering limitations, log shipping filter requirements.
- **Config v2 Specification**: [OpenTelemetry OBI Config v2 Reference](https://opentelemetry.io/docs/zero-code/obi/configure/config-v2/)
- **Migration Guide**: [Migrating to Config v2](https://opentelemetry.io/docs/zero-code/obi/configure/migrate-to-config-v2/)

---

## 3. GitHub Repositories & Internal Developer Docs
- **OpenTelemetry eBPF Instrumentation Repository**:
  - GitHub: [open-telemetry/opentelemetry-ebpf-instrumentation](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation)
- **Kernel Internals & Developer Documentation**:
  - [devdocs/trace-log-correlation.md](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/main/devdocs/trace-log-correlation.md)
  - Details: `traces_ctx_v1` BPF hash map, context staleness refresh across goroutines, write syscall hooks, `bpf_probe_write_user` semantics.
- **Official Docker Compose Demo Gist**:
  - Gist: [mmat11/f3f23707e7bc9c94bce144f56276251d](https://gist.github.com/mmat11/f3f23707e7bc9c94bce144f56276251d)

---

## 4. Local Architecture Guides in this Repository
- [architecture.md](architecture.md) — Comprehensive kernel syscall mechanics, LRU maps, memory suppression, and 8 KiB boundary.
- [runtime-compatibility.md](runtime-compatibility.md) — Detailed runtime breakdown (Go, Node.js, Java, Python, .NET, Ruby) solving context staleness.
- [day0-planning-sizing.md](day0-planning-sizing.md) — Preflight planning, kernel compatibility matrix, and hardware sizing.
- [day1-installation.md](day1-installation.md) — Installation and multi-cloud Kubernetes deployment runbooks.
- [day2-operations-triage.md](day2-operations-triage.md) — Operational queries (LogQL, Jaeger, Elasticsearch) and alert configurations.
- [log-filtering-guide.md](log-filtering-guide.md) — Deep dive into NUL byte placeholder lines and log shipper drop filters.
- [troubleshooting.md](troubleshooting.md) — Operational diagnostic runbook for edge cases and errors.
- [decommission-guide.md](decommission-guide.md) — Clean teardown and BPF map unpinning procedures.

---

## 5. Community & Support
- **CNCF Slack**: [#otel-ebpf-instrumentation](https://cloud-native.slack.com/archives/C06DQ7S2YEP)
- **OpenTelemetry Community Meetings**: Join the bi-weekly eBPF SIG meeting on the CNCF public calendar.
- **Issue Tracker**: [Report OBI Issues](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues)


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Decommission & Teardown Guide**](decommission-guide.md) | [**Repository Overview**](../README.md) | [**Official Blog Announcement**](reference-blog-announcement.md) |

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
