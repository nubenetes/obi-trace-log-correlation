# Amazon Elastic Kubernetes Service (EKS) Deployment Guide: OBI Trace-Log Correlation

## 1. Node AMI Architecture & Kernel Requirements
OBI trace-log correlation requires Linux kernel 6.0+.
- **Recommended AMI**: **Amazon Linux 2023 (AL2023)** which ships with Linux 6.1+.
- **Alternative**: **Bottlerocket OS** (kernel 6.1+).
- *Avoid legacy Amazon Linux 2 (AL2)* for trace-log correlation as it defaults to Linux 5.10.

To verify your EKS node kernel versions:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion
```

## 2. Pod Security Admission & AWS VPC CNI Coexistence
OBI operates alongside AWS VPC CNI eBPF features without interference because OBI hooks into application thread writes (`tty_write`, `pipe_write`, `ksys_write`, `do_writev`) and user-space uprobes rather than TC/XDP packet processing hooks.

Namespace configuration:
```bash
kubectl label namespace obi pod-security.kubernetes.io/enforce=privileged --overwrite
```

## 3. Deployment
```bash
kubectl apply -k k8s/overlays/eks
kubectl rollout status ds/obi -n obi
```
