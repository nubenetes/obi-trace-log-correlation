# Day 1: Installation & Multi-Cluster Deployment Guide

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

## 3. Generate Traffic & Verify Initial Ingestion

Once the cluster is bootstrapped, send requests to trigger trace propagation and log correlation:

```bash
# Port-forward frontend service
kubectl port-forward -n demo-apps svc/frontend 8080:8080 &

# Send synthetic load
./scripts/day1-generate-traffic.sh http://localhost:8080/checkout 10

# Verify cross-service correlation
./scripts/day2-verify-correlation.sh
```
