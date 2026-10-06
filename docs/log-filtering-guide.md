# Log Shipper Filtering Guide: Dropping Suppressed NUL Byte Placeholders

## 1. Why Suppressed Lines Contain NUL Bytes

When an application invokes `write()` or `writev()` on stdout or stderr, the Linux kernel prepares to transfer the user-space memory buffer to the container's standard output pipe.

To prevent the container runtime (CRI-O, containerd, Docker) from logging **two identical lines** (the original un-enriched line and the enriched line), OBI's kernel probe performs an in-memory suppression:

1. **Interception**: eBPF intercepts the write syscall before the bytes reach the pipe buffer.
2. **Buffering**: eBPF reads the user buffer into kernel memory and dispatches it to the user-space ring buffer.
3. **Suppression via `bpf_probe_write_user`**: The eBPF program calls the kernel helper `bpf_probe_write_user()` to overwrite the application's original user-space memory buffer with zeroes (`\0` / NUL bytes) terminated by `\n`.
4. **Re-Emission**: OBI's user-space daemon injects `trace_id` and `span_id` and writes the enriched line back to the file descriptor.

As a direct consequence, the raw container log file on disk (`/var/log/pods/*/*/*.log`) receives:
- One line consisting solely of NUL (`\x00`) characters terminated by `\n` (the suppressed placeholder).
- One enriched line containing the full log message with `trace_id` and `span_id`.

---

## 2. The 8 KiB Write Boundary

> [!WARNING]
> OBI enriches and suppresses at most the first **8 KiB** of a single `write()` or `writev()`.
> If an application writes a single log record exceeding 8 KiB:
> - The first 8 KiB is enriched and replaced with NUL bytes.
> - The remaining bytes pass through un-enriched into the log stream and **will not match** the placeholder filter.
> Always ensure application log formatters avoid emitting single monolithic writes larger than 8 KiB (e.g. huge stack traces with mega payloads).

---

## 3. Log Shipper Filter Configurations

Your log forwarding pipeline must filter out records that match `^[\x00\s]*$`. Below are drop configurations for all major enterprise log forwarders:

### A. OpenTelemetry Collector (`filelog` receiver)
```yaml
receivers:
  filelog:
    include:
      - /var/log/pods/*/*/*.log
    start_at: end
    operators:
      # Step 1: Parse container runtime log format (CRI / Docker)
      - type: container
        id: container-parser
      # Step 2: Drop placeholder lines filled with NUL characters
      - type: filter
        id: drop-obi-nul-placeholders
        expr: 'body matches "^[\\x00\\s]*$"'
```

### B. Vector (Vector Remap Language / Filter Transform)
```toml
[transforms.filter_obi_nul_placeholders]
type = "filter"
inputs = ["kubernetes_logs"]
condition = '!match(string!(.message), r"^[\x00\s]*$")'
```

### C. Fluent Bit
```ini
[FILTER]
    Name    grep
    Match   kube.*
    Exclude log ^[\x00\s]*$
```

### D. Promtail / Grafana Alloy
```yaml
scrape_configs:
  - job_name: kubernetes-pods
    pipeline_stages:
      - cri: {}
      - drop:
          expression: "^[\\x00\\s]*$"
```
