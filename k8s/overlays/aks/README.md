# Azure Kubernetes Service (AKS) Deployment Guide: OBI Trace-Log Correlation

## 1. Overview & Node Image Selection
OBI requires Linux kernel 6.0+ for trace-log correlation. On AKS:
- **Recommended Node OS**: **Azure Linux (CBL-Mariner 2.0 / Azure Linux 3.0)** or **Ubuntu 24.04**.
- Ubuntu 22.04 LTS (kernel 5.15) supports `writev()` but requires Linux 6.0+ for comprehensive `write()` (`ITER_UBUF`) log enrichment.

Verify node kernel versions:
```bash
kubectl get nodes -o wide
```

## 2. Pod Security Admission (PSA) & Azure Policy
Ensure the `obi` namespace has the `privileged` Pod Security standard enforced:
```bash
kubectl label namespace obi pod-security.kubernetes.io/enforce=privileged --overwrite
```
If Azure Policy with Gatekeeper is deployed in deny mode for privileged containers, add an exemption for namespace `obi`.

## 3. Log Ingestion Pipeline
If shipping logs to Azure Monitor / Container Insights or Grafana Loki:
- Deploy the in-cluster OpenTelemetry Collector DaemonSet (`k8s/base/otel-collector.yaml`) to tail `/var/log/pods` and drop NUL placeholder bytes (`^[\x00\s]*$`).

## 4. Deploying to AKS
```bash
kubectl apply -k k8s/overlays/aks
kubectl rollout status ds/obi -n obi
```
