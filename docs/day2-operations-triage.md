# Day 2: Operations, Incident Triage & Canary Rollout Guide

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [📈 Grafana & K8s](grafana-and-k8s-observability.md) &nbsp;|&nbsp; [📊 Metrics & Telemetry](ebpf-metrics-and-telemetry.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


## 1. Incident Triage Playbook: Correlating Traces to Logs

When an incident occurs and an alert fires, trace-log correlation cuts Mean Time To Resolution (MTTR) dramatically.

### Scenario: Paged on 502 Bad Gateway
1. **Locate the Trace in Jaeger**:
   - Open Jaeger UI (`http://localhost:16686`).
   - Query for errors or high latency on service `frontend`.
   - Copy the failing `trace_id` (e.g., `4bf92f3577b34da6a3ce929d0e0e4736`).

2. **Jump to Correlated Logs**:
   - In Grafana Loki, query directly by trace ID:
     ```logql
     {namespace="demo-apps"} |= "4bf92f3577b34da6a3ce929d0e0e4736"
     ```
   - In Elasticsearch / OpenSearch:
     ```json
     {
       "query": {
         "term": { "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736" }
       }
     }
     ```
   - In AWS CloudWatch Logs Insights:
     ```sql
     fields @timestamp, @message
     | filter trace_id = '4bf92f3577b34da6a3ce929d0e0e4736'
     | sort @timestamp desc
     ```

3. **Diagnose the Root Cause**:
   - Every log line across every microservice executing that transaction appears in perfect chronological order.
   - You immediately observe the backend database timeout line containing the exact query parameters without searching through gigabytes of unrelated logs.

### Multi-Cluster Federated Triage

In multi-region or hybrid architectures (e.g., EKS in AWS + AKS in Azure + on-premise OpenShift):
- **Cross-Cluster LogQL Query**:
  ```logql
  {cluster=~"prod-(aws|azure|onprem)", namespace="checkout"} |= "4bf92f3577b34da6a3ce929d0e0e4736"
  ```
- **Cross-Cluster Elasticsearch / OpenSearch DSL**:
  ```json
  {
    "query": {
      "bool": {
        "must": [
          { "term": { "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736" } },
          { "terms": { "k8s.cluster.name": ["prod-us-east", "prod-eu-west"] } }
        ]
      }
    }
  }
  ```

---

## 2. Progressive Canary Rollout Strategy

Do not enable log trace annotation on 100% of production workloads simultaneously. Roll out incrementally:

```mermaid
flowchart LR
    S1["Phase 1: Deploy OBI DaemonSet (Capture Only, Annotation Disabled)"] --> S2["Phase 2: Add 1 Low-Risk Service to 'match' (Verify NUL Filtering)"]
    S2 --> S3["Phase 3: Verify Single Log Ingestion (No Duplicates, No Splits)"]
    S3 --> S4["Phase 4: Expand 'match' to Entire Service Fleet"]
```

### Canary Automation with Script
```bash
# Check current annotation status
./scripts/day2-canary-rollout.sh status

# Enable annotation for frontend canary
./scripts/day2-canary-rollout.sh enable /frontend

# If an anomaly occurs, rollback instantly without touching the app
./scripts/day2-canary-rollout.sh disable /frontend

# Global emergency shutoff
./scripts/day2-canary-rollout.sh disable-all
```

### Node-Level Canary DaemonSet Deployment

In production clusters with hundreds of worker nodes, roll out the OBI DaemonSet itself to a 10% canary node group before scheduling across the entire fleet:

1. **Label Canary Nodes**:
   ```bash
   kubectl label node worker-node-01 worker-node-02 node-role.kubernetes.io/obi-canary="true"
   ```
2. **Apply Canary DaemonSet**:
   ```yaml
   apiVersion: apps/v1
   kind: DaemonSet
   metadata:
     name: obi-canary
     namespace: obi
   spec:
     template:
       spec:
         nodeSelector:
           node-role.kubernetes.io/obi-canary: "true"
   ```
3. **Verify Node Stability**:
   Monitor node kernel logs (`dmesg -w`) and BPF map allocations for 24 hours. Once verified, promote to the default DaemonSet targeting all worker nodes.

### Zero-Downtime Hot Rollback Procedure

If an anomaly occurs (e.g. an unhandled runtime buffer split or downstream log ingestion spike):
1. **Instant Annotation Disable (Hot Unhook)**:
   Dynamically set `log_trace_annotation.enabled: false` in the `obi-config` ConfigMap:
   ```bash
   kubectl patch configmap obi-config -n obi --type merge -p '{"data":{"obi-config.yml":"extensions:\n  obi:\n    correlation:\n      log_trace_annotation:\n        enabled: false\n"}}'
   ```
   *Result*: The eBPF hook detaches from `sys_enter_write` within **50 milliseconds**. Application pods continue running with zero downtime or restarts.
2. **Emergency Global Rollback via Script**:
   ```bash
   ./scripts/day2-canary-rollout.sh disable-all
   ```

---

## 3. Operational Monitoring & Alerting

Monitor the health of OBI and the eBPF subsystem using Prometheus metrics exported on port 8999:

| Metric | Threshold | Alert Severity | Description |
|---|---|---|---|
| `obi_bpf_map_entries{map="traces_ctx_v1"}` | > 85% capacity | Warning | The thread LRU map is near saturation; consider increasing map size |
| `obi_ringbuffer_dropped_events_total` | > 0 | Critical | Log events are being dropped due to user-space writer backpressure |
| `obi_enricher_errors_total` | > 10 / min | Warning | Syscall write interception encountered read/write failures |
| `container_cpu_usage_seconds_total{container="obi"}` | > 80% limit | Warning | OBI CPU throttling; increase resource limits |

> [!NOTE]
> For a complete PromQL reference catalog, application RED metrics formulas, Prometheus Exemplars, and `PrometheusRule` alerting CRDs, see 📊 [**Metrics & Telemetry Architecture Guide**](ebpf-metrics-and-telemetry.md).


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Day 1: Multi-Cluster Deployment**](day1-installation.md) | [**Repository Overview**](../README.md) | [**Log Shipper Filtering Guide**](log-filtering-guide.md) |

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
