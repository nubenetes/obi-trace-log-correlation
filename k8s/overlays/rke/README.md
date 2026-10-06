# Rancher RKE / RKE2 / K3s Deployment Guide: OBI Trace-Log Correlation

## 1. Node OS & CIS Hardening
RKE2 clusters typically run on hardened enterprise distributions (RHEL, Rocky, SLES, Ubuntu).
Ensure the underlying Linux host kernel is **6.0 or later**.

In CIS-hardened profiles:
- Verify that `/sys/fs/bpf` is mounted on the host:
  ```bash
  mount | grep bpf
  ```
  If not mounted, mount it:
  ```bash
  sudo mount -t bpf bpffs /sys/fs/bpf
  ```
- Ensure Pod Security Admission is configured to allow `privileged` on namespace `obi`.

## 2. Deployment
```bash
kubectl apply -k k8s/overlays/rke
kubectl rollout status ds/obi -n obi
```
