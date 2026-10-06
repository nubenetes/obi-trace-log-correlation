# Local Evaluation via Docker Compose

This directory provides a minimal, self-contained environment to evaluate **OpenTelemetry eBPF Instrumentation (OBI)** trace-log correlation on a single Linux machine.

---

## Architecture

The stack launches 4 containers:
1. **`frontend`** (Port 8080): Uninstrumented Go HTTP microservice emitting JSON logs using `log/slog`.
2. **`backend`** (Port 8081): Uninstrumented Go HTTP microservice handling requests from `frontend` and emitting JSON logs.
3. **`jaeger`** (Port 16686 & 4317): All-in-one distributed tracing backend receiving OTLP spans.
4. **`obi`**: OpenTelemetry eBPF agent running with `pid: host` and `privileged: true`, attaching kernel probes to inject `trace_id` and `span_id` into stdout writes.

---

## Prerequisites

- **Host Kernel**: Linux 6.0 or later (`uname -r`).
- **BPF Filesystem**: Mounted at `/sys/fs/bpf`.
- **Privileges**: Root / Docker daemon access capable of mounting `/sys/fs/bpf` and running privileged containers.
- **Kernel Lockdown**: Not in integrity or confidentiality lockdown mode (`cat /sys/kernel/security/lockdown`).

---

## Quickstart

### 1. Start the Stack
```bash
docker compose up -d --build
```

Wait ~5-10 seconds for OBI to initialize BPF probes and attach to the running processes.

### 2. Trigger a Transaction
Send an HTTP request through the frontend:
```bash
curl -i http://localhost:8080/checkout
```

Expected output:
```json
{"status":"completed","order_id":"ord-48192","backend_response":"hello from backend service (processed in 23.41ms)"}
```

### 3. Inspect Enriched Logs
Check the logs emitted by both services:
```bash
docker compose logs frontend backend | grep -a trace_id
```

Notice that both logs now carry:
- Matching `trace_id` linking the two hops across network boundaries.
- Distinct `span_id` values identifying each microservice's execution unit.

Example output:
```json
frontend-1  | {"amount":42.5,"currency":"USD","level":"INFO","msg":"payment authorized","order_id":"ord-48192","span_id":"00f067aa0ba902b7","time":"2026-10-06T13:25:00Z","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"}
backend-1   | {"client_ip":"172.18.0.3:54210","db_query_latency":"23.41ms","items_retrieved":7,"level":"INFO","msg":"handling request in backend","path":"/hello","span_id":"278a9c1e55fa4189","time":"2026-10-06T13:25:00Z","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"}
```

### 4. Visualize in Jaeger UI
Open your browser at **http://localhost:16686**:
1. Select service `frontend` in the search dropdown.
2. Search for traces or paste the `trace_id` extracted from the logs into the search bar.
3. Observe the complete distributed trace connecting `frontend` -> `backend`.

### 5. Tear Down
```bash
docker compose down -v
```
