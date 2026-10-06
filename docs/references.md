# References & Official Documentation

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
