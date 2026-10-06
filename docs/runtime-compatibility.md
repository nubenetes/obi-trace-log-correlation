# Runtime Compatibility & Language Guidance

OBI trace-log correlation associates log writes with requests by identifying the active trace context on the thread or goroutine performing the syscall. Runtimes handle stdout buffering differently. Follow this guidance per language runtime.

---

## 1. Go Runtime
- **Compatibility**: **Tier 1 (Flawless)**.
- **Loggers**: Standard library `log/slog`, Uber `zap`, `zerolog`.
- **Mechanism**: Go executes writes synchronously on the OS thread assigned to the executing goroutine. OBI's uprobe hooks (`runtime.casgstatus`) refresh context when goroutines switch between OS threads.
- **Zero code or configuration required**.

---

## 2. Python Runtime
- **Compatibility**: **Supported with 1 Environment Variable**.
- **Loggers**: Standard `logging`, `structlog`, `loguru`.
- **Crucial Requirement**: Python buffers standard output by default when connected to a container pipe.
  ```dockerfile
  ENV PYTHONUNBUFFERED=1
  ```
- Without `PYTHONUNBUFFERED=1`, log flushes are deferred to arbitrary background intervals or thread exits, losing association with the active HTTP request context.

---

## 3. Java Runtime
- **Compatibility**: **Supported for Platform Threads**.
- **Loggers**: Logback, Log4j2, `java.util.logging`.
- **Platform Threads**: Supported out-of-the-box via standard console appenders (`ConsoleAppender` with `LogstashEncoder`).
- **Virtual Threads (Project Loom)**:
  > [!IMPORTANT]
  > Java virtual threads are **not yet enriched**.
  > Because multiple virtual threads share and jump across underlying OS carrier threads, correlation cannot currently distinguish virtual thread boundaries at the kernel level.
  > Platform-thread workloads are completely unaffected.

---

## 4. Node.js Runtime
- **Compatibility**: **Supported**.
- **Loggers**: `pino`, `winston`, `console.log`.
- **Mechanism**: OBI hooks Node.js `async_hooks` before callbacks to track asynchronous event loops.
- **Backpressure Notice**: Node.js stdout writes can become asynchronous under heavy I/O backpressure. Ensure stdout pipes do not saturate.

---

## 5. .NET Runtime
- **Compatibility**: **Supported with Synchronous Console Writer**.
- **Loggers**: Serilog, Microsoft.Extensions.Logging.
- **Crucial Requirement**: By default, ASP.NET Core `AddConsole()` logs via a background queue thread. To correlate with OBI, configure a synchronous console writer with auto-flush:
  ```csharp
  var writer = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true };
  Console.SetOut(writer);
  ```

---

## 6. Coexistence with OpenTelemetry SDKs (Hybrid Mode)

If a service already uses an OpenTelemetry SDK (e.g. for traces) but does **not** export logs with trace context:
- OBI detects the SDK export and **only injects `trace_id`**.
- It deliberately suppresses injecting `span_id` because OBI's eBPF-generated span IDs will not match the SDK's internal child spans.
- This preserves data integrity while still enabling complete trace-to-log correlation by `trace_id`.
