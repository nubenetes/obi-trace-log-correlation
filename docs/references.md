# References & Official Documentation

This reference guide catalogs all official OpenTelemetry documentation, blog posts, repositories, and community resources related to **OpenTelemetry eBPF Instrumentation (OBI)** and zero-code trace-log correlation.

---

## 1. Official Announcements & Articles
- **OpenTelemetry Blog Post**: [Zero-code trace-log correlation with OBI](https://opentelemetry.io/blog/2026/obi-trace-log-correlation/)
  - *Summary*: Primary announcement detailing the motivation, kernel interception mechanism, JSON/plain-text formatting, and rollout guidance.
- **Markdown Version**: [Blog Index Markdown](https://opentelemetry.io/blog/2026/obi-trace-log-correlation/index.md)

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

## 4. Community & Support
- **CNCF Slack**: [#otel-ebpf-instrumentation](https://cloud-native.slack.com/archives/C06DQ7S2YEP)
- **OpenTelemetry Community Meetings**: Join the bi-weekly eBPF SIG meeting on the CNCF public calendar.
- **Issue Tracker**: [Report OBI Issues](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues)
