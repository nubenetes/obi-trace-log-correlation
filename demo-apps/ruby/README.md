# Ruby (Puma) Demo Microservice

This microservice demonstrates how Ruby applications running under the **Puma 6.x** application server interact with **OpenTelemetry eBPF Zero-Code Trace-Log Correlation (OBI)**.

---

## 1. Architectural Analysis: Puma Concurrency & Stdout Buffering

### Multi-Process (Clustered) vs Multi-Threaded Mode
* **Clustered Mode (`WEB_CONCURRENCY > 0`)**: Puma forks multiple worker OS processes, each with its own independent Linux `PID`. When OBI monitors socket ingress, each worker process maintains an isolated trace context entry in the kernel BPF map (`traces_ctx_v1`). There is zero cross-process trace leakage.
* **Threaded Mode (`threads min, max`)**: Within a single Puma worker, requests run concurrently on separate Ruby threads managed by the Ruby VM (MRI GVL / Global VM Lock). OBI relies on runtime context hooks (`rb_ary_shift` / Fiber scheduler) to track active thread transitions.

### The `STDOUT.sync = true` Requirement
In Ruby, when standard output (`$stdout`) is attached to a terminal (TTY), it is line-buffered. However, inside a Linux container (Docker/containerd), stdout is connected to a **non-TTY UNIX pipe**. By default, Ruby's standard I/O layer switches to **8 KiB block buffering**.

* **Failure Mode (`STDOUT.sync = false`)**: Log messages remain in Ruby user-space memory until 8 KiB accumulates or the process terminates. By the time the `write(1, ...)` syscall is executed, the original HTTP request socket has closed, and OBI loses trace context.
* **Remediation (`STDOUT.sync = true`)**: Setting `STDOUT.sync = true` bypasses block buffering and forces immediate, synchronous `write()` syscalls on fd 1, preserving exact trace-log correlation.

---

## 2. Directory Structure

* [`app.rb`](app.rb): Rack application with structured JSON logging and configurable `STDOUT.sync`.
* [`config.ru`](config.ru): Standard Rack application entry point.
* [`puma.rb`](puma.rb): Puma configuration configuring worker processes, thread pools, and worker boot hooks.
* [`Gemfile`](Gemfile): Bundler dependencies (`puma`, `rack`).
* [`Dockerfile`](Dockerfile): Multi-stage container build based on `ruby:3.3-alpine` running as non-root user `10001:10001`.

---

## 3. Working vs Broken Modes

| Mode | Environment Variable | Stdout Buffering | OBI Correlation Behavior |
| :--- | :--- | :--- | :--- |
| **Working (Default)** | `RUBY_SYNC_STDOUT=true` | Immediate sync flush (`STDOUT.sync = true`) | ✅ **100% Correlated**: Immediate `write()` syscall executes while request context is active. |
| **Broken** | `RUBY_SYNC_STDOUT=false` | 8 KiB block buffering | ⚠️ **Trace Lost**: Log writes are delayed until 8 KiB accumulates, losing socket context. |

---

## 4. Building and Running

### Build the Container Image
```bash
docker build -t obi-demo-ruby:latest demo-apps/ruby/
```

### Run in Working Mode (Immediate Sync)
```bash
docker run --rm -p 8085:8085 -e RUBY_SYNC_STDOUT=true obi-demo-ruby:latest
```

### Run in Broken Mode (Block Buffered)
```bash
docker run --rm -p 8085:8085 -e RUBY_SYNC_STDOUT=false obi-demo-ruby:latest
```

### Test Transaction
```bash
curl -i -X POST http://localhost:8085/process \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
  -d '{"order_id":"rb-1029","amount":49.99}'
```
