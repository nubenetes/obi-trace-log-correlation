# Troubleshooting & Diagnostic Runbook

This runbook covers common issues encountered when deploying and operating OBI trace-log correlation.

---

## 1. Trace Context Not Appearing in Logs

### Symptom
Application logs are written to stdout, but `trace_id` and `span_id` are absent.

### Diagnostics
1. **Is the workload matched in OBI configuration?**
   Inspect `obi-config.yml`:
   ```yaml
   extensions:
     obi:
       correlation:
         log_trace_annotation:
           enabled: true
           match:
             - process:
                 exe_path_glob:
                   - /frontend
   ```
   *Rule*: A process must be included in **both** `capture.rules` AND `log_trace_annotation.match`.

2. **Is the log written during an active trace?**
   OBI only injects trace context when a request or operation is in-flight on that thread.
   - Logs written at service startup or in background timers pass through untouched.
   - Send active HTTP traffic: `curl http://localhost:8080/checkout`.

3. **Is stdout buffered?**
   - In Python, verify `PYTHONUNBUFFERED=1` is set in the container environment.
   - In .NET, ensure synchronous console output is active.

---

## 2. Blank Lines / NUL Characters Visible in Log Backend

### Symptom
Log dashboards (Loki, Elasticsearch, CloudWatch) show empty lines or strings containing `\u0000` / `\x00`.

### Solution
The log shipping pipeline is missing the drop filter. OBI zeroes out original user buffers before re-emitting enriched lines.
Update your log shipper with the regex filter:
```regex
^[\x00\s]*$
```
See the [Log Shipper Filtering Guide](log-filtering-guide.md) for full configuration blocks.

---

## 3. Large Log Writes Splitting (> 8 KiB)

### Symptom
A long stack trace or JSON payload appears split across two log records, with only the first part enriched.

### Root Cause
OBI suppresses and enriches at most the first **8 KiB** of a single `write()` or `writev()` call.
Any bytes beyond 8 KiB pass through into the log stream un-enriched.

### Remediation
- Configure log formatters to truncate oversized payload dumps or stack frames to <= 8 KiB.
- Ship massive unstructured payloads to object storage (S3/GCS) and log only the reference URL.

---

## 4. Kernel Lockdown Denials

### Symptom
OBI pod fails to start with errors like:
```text
bpf_probe_write_user: Operation not permitted
```

### Root Cause
The Linux kernel is running in Secure Boot Lockdown mode (`integrity` or `confidentiality`). Kernel lockdown blocks `bpf_probe_write_user` to prevent arbitrary memory overwrites.

### Diagnostic Command
```bash
cat /sys/kernel/security/lockdown
# Returns: [none] integrity confidentiality
```
If `[integrity]` or `[confidentiality]` is enclosed in brackets, lockdown is active.
Disable lockdown in host BIOS/GRUB or use standard cloud virtual machines without locked EFI secure boot policies.

---

## 5. OpenShift Permission Denied / SCC Issues

### Symptom
In OpenShift 4.20+, the OBI pod is rejected by the admission controller with `forbidden: not authorized by any SecurityContextConstraints`.

### Remediation
Bind the dedicated `obi-ebpf-scc` to the ServiceAccount:
```bash
oc adm policy add-scc-to-user obi-ebpf-scc -z obi-agent -n obi
```
Or allow the built-in `privileged` SCC:
```bash
oc adm policy add-scc-to-user privileged -z obi-agent -n obi
```
