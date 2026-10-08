# Day 1: Installation & Multi-Cluster Deployment Guide

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🌐 Frontend](frontend-spa-ssr-telemetry.md) &nbsp;|&nbsp; [🕸️ Service Mesh](service-mesh-vs-ebpf-observability.md) &nbsp;|&nbsp; [📊 Tool Comparison](obi-vs-modern-observability-tools.md) &nbsp;|&nbsp; [📈 Grafana & K8s](grafana-and-k8s-observability.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


This guide provides step-by-step deployment instructions for rolling out OpenTelemetry eBPF Instrumentation (OBI) with trace-log correlation on major Kubernetes distributions and local testbeds.

---

## 1. Automated Deployment via Script

The quickest way to deploy is using the unified script `scripts/day1-deploy.sh`:

```bash
# For OpenShift 4.20+
./scripts/day1-deploy.sh --cluster openshift

# For Azure Kubernetes Service (AKS)
./scripts/day1-deploy.sh --cluster aks

# For AWS Elastic Kubernetes Service (EKS)
./scripts/day1-deploy.sh --cluster eks

# For Google Kubernetes Engine (GKE Standard)
./scripts/day1-deploy.sh --cluster gke

# For Rancher RKE2 / K3s
./scripts/day1-deploy.sh --cluster rke

# For Local Docker Compose
./scripts/day1-deploy.sh --cluster docker-compose
```

---

## 2. Manual Distribution Walkthroughs

### A. Red Hat OpenShift 4.20+

1. **Apply the OpenShift overlay**:
   ```bash
   oc apply -k k8s/overlays/openshift-4.20
   ```
2. **Authorize the ServiceAccount with the custom SCC**:
   ```bash
   oc adm policy add-scc-to-user obi-ebpf-scc -z obi-agent -n obi
   ```
3. **Verify DaemonSet Rollout**:
   ```bash
   oc rollout status ds/obi -n obi
   ```

---

### B. Azure Kubernetes Service (AKS)

1. **Verify Nodes Run Kernel >= 6.0**:
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion
   ```
2. **Deploy the AKS Overlay**:
   ```bash
   kubectl apply -k k8s/overlays/aks
   ```
3. **Verify OBI DaemonSet**:
   ```bash
   kubectl rollout status ds/obi -n obi
   ```

---

### C. AWS Elastic Kubernetes Service (EKS)

1. **Deploy the EKS Overlay**:
   ```bash
   kubectl apply -k k8s/overlays/eks
   ```
2. **Expose Jaeger Web UI (Optional for Testing)**:
   ```bash
   kubectl port-forward -n obi svc/jaeger 16686:16686 &
   ```

---

### D. Google Kubernetes Engine (GKE Standard)

1. **Deploy the GKE Overlay**:
   ```bash
   kubectl apply -k k8s/overlays/gke
   ```
2. **Confirm Pods Status**:
   ```bash
   kubectl get pods -n obi -o wide
   ```

---

### E. Rancher RKE2 / K3s

1. **Verify Host Kernel & BPF Filesystem**:
   RKE2 and K3s nodes must run Linux kernel 6.0 or later. In hardened CIS profiles, verify that `/sys/fs/bpf` is mounted on the host:
   ```bash
   mount | grep bpffs
   # If missing, mount on the host:
   sudo mount -t bpf bpffs /sys/fs/bpf
   ```
2. **Configure Pod Security Standards**:
   Ensure the `obi` namespace allows privileged execution:
   ```bash
   kubectl create namespace obi --dry-run=client -o yaml | kubectl apply -f -
   kubectl label namespace obi --overwrite pod-security.kubernetes.io/enforce=privileged
   ```
3. **Deploy the RKE2 Overlay**:
   ```bash
   kubectl apply -k k8s/overlays/rke
   ```
4. **Confirm DaemonSet Rollout**:
   ```bash
   kubectl rollout status ds/obi -n obi
   ```

---

## 3. Declarative GitOps Deployment (ArgoCD & Flux)

In enterprise multi-cluster environments, deploy OBI across development, staging, and production clusters using GitOps controllers.

### A. ArgoCD Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: obi-daemonset
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/nubenetes/obi-trace-log-correlation.git
    targetRevision: main
    # Select target distribution overlay (e.g. aks, eks, openshift-4.20, gke, rke)
    path: k8s/overlays/aks
  destination:
    server: https://kubernetes.default.svc
    namespace: obi
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### B. Flux CD Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: obi-daemonset
  namespace: flux-system
spec:
  interval: 10m
  path: "./k8s/overlays/eks"
  prune: true
  sourceRef:
    kind: GitRepository
    name: obi-trace-log-correlation
  targetNamespace: obi
  timeout: 3m
```

---

## 4. Generate Traffic & Verify Initial Ingestion

Once the cluster is bootstrapped, send requests to trigger trace propagation and log correlation:

```bash
# Port-forward frontend service
kubectl port-forward -n demo-apps svc/frontend 8080:8080 &

# Send synthetic load
./scripts/day1-generate-traffic.sh http://localhost:8080/checkout 10

# Verify cross-service correlation
./scripts/day2-verify-correlation.sh
```


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Day 0: Planning & Sizing**](day0-planning-sizing.md) | [**Repository Overview**](../README.md) | [**Day 2: Operations & Incident Triage**](day2-operations-triage.md) |

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
