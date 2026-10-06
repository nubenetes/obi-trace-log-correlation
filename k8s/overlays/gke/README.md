# Google Kubernetes Engine (GKE) Deployment Guide: OBI Trace-Log Correlation

## 1. GKE Cluster Mode (Standard vs Autopilot)
> [!IMPORTANT]
> OBI trace-log correlation requires host-level eBPF attaching via `hostPID: true`, `privileged: true`, and mounting `/sys/fs/bpf`.
> Therefore, **GKE Standard** cluster mode is required. GKE Autopilot clusters restrict privileged DaemonSets and host path mounts.

## 2. Node Image Selection
- Choose **Container-Optimized OS (COS)** or **Ubuntu** image type. Modern COS versions run Linux kernel 6.1+.
- Verify kernel on your nodes:
  ```bash
  kubectl get nodes -o wide
  ```

## 3. Coexistence with GKE Datapath V2
GKE Datapath V2 utilizes Cilium eBPF for networking. OBI instruments application level HTTP/gRPC traffic and intercepting standard stream write calls; it operates alongside Datapath V2 without conflicts on the eBPF subsystem.

## 4. Deployment
```bash
kubectl apply -k k8s/overlays/gke
kubectl rollout status ds/obi -n obi
```
