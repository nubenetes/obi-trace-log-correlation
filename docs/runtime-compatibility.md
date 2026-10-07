# Runtime Compatibility & Language Guidance: Solving Context Staleness in OBI

> **Reference Documentation**:
> - [Zero-Code Trace-Log Correlation with OBI (Official Blog Announcement)](reference-blog-announcement.md)
> - [Kernel Internals & Developer Spec (devdocs/trace-log-correlation.md)](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/main/devdocs/trace-log-correlation.md)

---

> **Documentation Hub**: [🏠 Overview](../README.md) &nbsp;|&nbsp; [📜 Announcement](reference-blog-announcement.md) &nbsp;|&nbsp; [🏛️ Architecture](architecture.md) &nbsp;|&nbsp; [📋 Day 0: Sizing](day0-planning-sizing.md) &nbsp;|&nbsp; [📦 Day 1: Deploy](day1-installation.md) &nbsp;|&nbsp; [🚨 Day 2: Ops](day2-operations-triage.md) &nbsp;|&nbsp; [💧 Log Filtering](log-filtering-guide.md) &nbsp;|&nbsp; [⚡ Runtimes](runtime-compatibility.md) &nbsp;|&nbsp; [🔧 Troubleshooting](troubleshooting.md) &nbsp;|&nbsp; [🧹 Decommission](decommission-guide.md) &nbsp;|&nbsp; [📚 References](references.md)

---


---

## Table of Contents
- [1. Executive Summary](#1-executive-summary)
- [2. The Fundamental Problem: Context Staleness Across Runtimes](#2-the-fundamental-problem-context-staleness-across-runtimes)
  - [The Junior Mental Model: The Restaurant Waiter Analogy](#the-junior-mental-model-the-restaurant-waiter-analogy)
  - [The Technical Problem: OS Threads vs Application Concurrency](#the-technical-problem-os-threads-vs-application-concurrency)
- [3. Per-Runtime Summary Table & Practical Guidance](#3-per-runtime-summary-table--practical-guidance)
  - [Architectural Dimensions of the Runtime Matrix](#architectural-dimensions-of-the-runtime-matrix)
  - [Go Runtime: Out-of-the-Box Success & Goroutine Pitfalls](#go-runtime-out-of-the-box-success--goroutine-pitfalls)
  - [Python Runtime: The Block Buffering Trap & Asyncio Fixes](#python-runtime-the-block-buffering-trap--asyncio-fixes)
  - [Node.js Runtime: Event Loop Alignment & Worker Thread Traps](#nodejs-runtime-event-loop-alignment--worker-thread-traps)
  - [Java Runtime: Platform Threads vs Project Loom Virtual Thread Failures](#java-runtime-platform-threads-vs-project-loom-virtual-thread-failures)
  - [.NET Runtime: ASP.NET Core Background Channel Dilemma & Solutions](#net-runtime-aspnet-core-background-channel-dilemma--solutions)
  - [Ruby Runtime: Puma Reactor Paths & Background Job Limits](#ruby-runtime-puma-reactor-paths--background-job-limits)
  - [Plain-Text & Legacy Monoliths: Non-JSON Key-Value Enrichment](#plain-text--legacy-monoliths-non-json-key-value-enrichment)
- [4. Deep Dive: Per-Runtime Kernel Refresh Mechanics](#4-deep-dive-per-runtime-kernel-refresh-mechanics)
  - [Go Runtime: `runtime.casgstatus` Uprobes](#go-runtime-runtimecasgstatus-uprobes)
  - [Node.js Runtime: `async_hooks` & `uv_fs_access`](#nodejs-runtime-async_hooks--uv_fs_access)
  - [Java Runtime: ByteBuddy & Thread Hierarchy `ioctl`](#java-runtime-bytebuddy--thread-hierarchy-ioctl)
  - [Ruby (Puma): Direct vs Reactor Path (`rb_ary_shift`)](#ruby-puma-direct-vs-reactor-path-rb_ary_shift)
  - [Python Runtime: CPython Asyncio & `PYTHONUNBUFFERED=1`](#python-runtime-cpython-asyncio--pythonunbuffered1)
  - [.NET Runtime: Synchronous Writers vs Background Channels](#net-runtime-synchronous-writers-vs-background-channels)
- [5. Coexistence with OpenTelemetry In-Process SDKs (Hybrid Mode)](#5-coexistence-with-opentelemetry-in-process-sdks-hybrid-mode)

---

## 1. Executive Summary

OBI correlates log writes with distributed traces by capturing the active `trace_id` and `span_id` associated with the executing thread. In a simplistic OS model, each incoming network request would be served from start to finish by a single dedicated operating system thread (`pid_tgid`).

However, modern high-performance runtimes (Go, Node.js, Python Asyncio, Java Netty/Tomcat) decouple I/O handling from CPU execution. Without runtime-aware kernel hooks, `traces_ctx_v1[pid_tgid]` would become stale, causing logs from one customer request to be incorrectly stamped with the trace ID of a different customer request.

This document explains the runtime specifics, requirements, and kernel probe mechanisms that solve context staleness.

---

## 2. The Fundamental Problem: Context Staleness Across Runtimes

### The Junior Mental Model: The Restaurant Waiter Analogy
Imagine a busy restaurant:
- **Waiter (OS Thread)**: The worker who runs back and forth between the kitchen and tables.
- **Order Slip (Trace Context)**: The customer's ticket (Ticket #101).
- **Notepad (Log Buffer)**: Where the worker writes down status notes ("Drink prepared").

In an old synchronous model, Waiter Bob took Ticket #101, walked to the bar, prepared the drink, wrote "Drink prepared" on Bob's notepad, and brought it to Table 101. Bob's badge ID was always tied to Ticket #101.

In a modern async model:
- Waiter Bob takes Ticket #101, hands the drink order to the bartender, and immediately walks over to Table 102 to take Ticket #102.
- When the bartender finishes the drink for Table 101, Waiter Alice happens to be walking past. Alice picks up the glass and writes "Drink prepared" on Alice's notepad.
- If OBI only checked "Who is Alice serving?", it might stamp Ticket #102 on Table 101's drink!

### The Technical Problem: OS Threads vs Application Concurrency
The kernel BPF map `traces_ctx_v1` is indexed by `u64 pid_tgid` (OS Process ID + Thread ID).
- **Go**: Multiplexes thousands of Goroutines ($G$) onto a pool of OS threads ($M$). A goroutine can yield on channel I/O or a network call, and resume on a completely different OS thread.
- **Node.js**: The single-threaded event loop processes multiple interleaved requests concurrently via `libuv`. Multiple HTTP requests arrive on the wire before any user JavaScript callback runs.
- **Java**: HTTP servers (Netty, Tomcat) use separate acceptor threads to read socket bytes, then pass tasks to worker thread pools.
- **Python**: In `asyncio`, an event loop runs many tasks on a single OS thread. When code hits `await`, the thread switches tasks.

To prevent context staleness, OBI hooks each runtime's internal scheduler to refresh `traces_ctx_v1` at the exact instant context switches occur.

---

## 3. Per-Runtime Summary Table & Practical Guidance

The matrix below provides an operational overview of how mainstream programming language runtimes behave with OBI eBPF zero-code trace-log correlation.

| Language Runtime | Default Stdout Buffering | Works Out of the Box? | Mandatory Configuration / Remediation | Context Refresh Hook | Risk of Context Staleness |
| :--- | :--- | :---: | :--- | :--- | :---: |
| **Go** | Synchronous `write()` | ✅ **Yes** | None (Zero-code / Zero-config) | `runtime.casgstatus` uprobes | Minimal (Except detached background goroutines) |
| **Python** | Block-buffered on pipes (8 KiB) | ⚠️ **Requires Env** | `ENV PYTHONUNBUFFERED=1` in Dockerfile | `_asyncio.Task.task_step` uprobes | **High** if unbuffered mode is omitted |
| **Node.js** | Synchronous stdout pipe | ✅ **Yes** | Use direct stdout stream; avoid worker-thread transports | `async_hooks` + `uv_fs_access` uprobe | Low (High if using thread-stream transports) |
| **Java (Platform Threads)** | Immediate `System.out` flush | ✅ **Yes** | Standard synchronous console appenders | ByteBuddy + `ioctl` (`k_ioctl_java_threads`) | Low with platform thread pools |
| **Java (Virtual Threads / Loom)** | Fiber carrier multiplexing | ❌ **Not Supported** | Do not rely on OBI for Loom fibers; use in-process OTel SDK | None (Virtual carrier hopping unmapped) | **Extreme** (Severe trace cross-contamination) |
| **.NET (C# / ASP.NET)** | Block-buffered (4 KB) | ⚠️ **Requires Code** | Serilog synchronous console sink or `AutoFlush = true` | Synchronous console appender required | **High** with default `AddConsole()` background channel |
| **Ruby (Puma)** | Synchronous `syswrite()` | ✅ **Yes** | Ensure `STDOUT.sync = true` in multi-process Puma | `rb_ary_shift` uprobes | Low within web worker threads |
| **Legacy Plain-Text (C/C++/Go)** | VFS write syscalls | ✅ **Yes** | None (Appends `trace_id=... span_id=...` key-value pairs) | Direct `sys_enter_write` kprobe | Minimal |

---

### Architectural Dimensions of the Runtime Matrix

To understand why some runtimes work effortlessly while others silently lose trace correlation, engineers must evaluate three fundamental architectural dimensions:

1. **User-Space Buffering vs Kernel System Calls**:
   - The Linux kernel eBPF probe operates strictly at the VFS syscall boundary (`sys_enter_write` and `sys_enter_writev`).
   - If an application's runtime or standard C library (`libc`) buffers output in user-space memory (e.g. 4 KiB or 8 KiB buffers), the actual `write()` syscall does not occur when the code executes `log.info(...)`.
   - Instead, the syscall is deferred until the buffer fills or the process exits. By that time, the thread has finished processing the original HTTP transaction, resulting in **either a completely missing trace ID or an incorrect trace ID from an unrelated subsequent request**.

2. **Thread Affinity vs Asynchronous Dispatch**:
   - The kernel identifies executing code by `bpf_get_current_pid_tgid()` (Thread Group ID + Process ID).
   - If a logging framework immediately hands log entries to a separate background thread pool, async channel, or worker thread (as seen in ASP.NET Core `AddConsole()` or Pino worker threads), the thread that actually issues the `write()` system call is **not** the thread that handled the request.
   - Without active thread-hierarchy tracking, the worker thread possesses no entry in the `traces_ctx_v1` BPF map.

3. **Runtime Scheduler Visibility**:
   - In cooperative multitasking runtimes (Go Goroutines, Python Asyncio, Node.js Event Loop), multiple units of application concurrency are multiplexed over one or more OS threads.
   - OBI requires runtime-specific uprobes (`runtime.casgstatus`, `async_hooks`, `_asyncio.Task.task_step`) to update `traces_ctx_v1` precisely as the runtime scheduler switches active execution contexts.

---

### Go Runtime: Out-of-the-Box Success & Goroutine Pitfalls

#### Why It Works Out of the Box
Go's runtime scheduler multiplexes $M$ operating system threads across $N$ goroutines. OBI hooks `runtime.casgstatus` to detect when a goroutine enters `_Grunning` or `_Gsyscall`. When an uninstrumented Go application logs via `log/slog` or `fmt.Println`, the runtime issues a direct `write()` syscall on the current OS thread $M$, allowing the eBPF probe to match `traces_ctx_v1[pid_tgid]` instantaneously.

#### ✅ Working Sample: Standard Go `log/slog` JSON Server
This is the pattern implemented in [`demo-apps/go/frontend/main.go`](../demo-apps/go/frontend/main.go):

```go
package main

import (
    "log/slog"
    "net/http"
    "os"
)

func main() {
    // Zero-code setup: Standard JSON handler writing directly to os.Stdout
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    http.HandleFunc("/api/order", func(w http.ResponseWriter, r *http.Request) {
        // OBI intercepts this stdout write and correlates it with the active HTTP trace!
        logger.Info("order received",
            slog.String("item", "widget-pro"),
            slog.Int("qty", 2),
        )
        w.WriteHeader(http.StatusOK)
    })

    http.ListenAndServe(":8080", nil)
}
```

#### ⚠️ When It Does NOT Work: Detached Background Goroutines
If an HTTP handler fires an unmonitored background goroutine that outlives the HTTP request or performs async work after returning, OBI's return uprobe clears the active HTTP trace context when the handler finishes:

```go
// ❌ BROKEN SCENARIO: Detached background goroutine loses trace context
http.HandleFunc("/api/order", func(w http.ResponseWriter, r *http.Request) {
    logger.Info("order accepted synchronously") // ✅ Correlated!

    // Fire-and-forget goroutine executing after HTTP response returns
    go func() {
        time.Sleep(200 * time.Millisecond)
        // ❌ FAILS: The HTTP request has finished. OBI's return probe cleared
        // the thread's trace context. This log line will NOT contain trace_id!
        logger.Info("async background notification dispatched")
    }()

    w.WriteHeader(http.StatusAccepted)
})
```

#### 💡 Remediation for Background Goroutines
For asynchronous tasks that outlive the HTTP request, pass context explicitly or log within the synchronous boundary:
```go
// ✅ REMEDIATION: Capture context or complete work within handler lifecycle
http.HandleFunc("/api/order", func(w http.ResponseWriter, r *http.Request) {
    logger.Info("processing order synchronously")
    
    // Complete async work with WaitGroup or bounded context before returning:
    done := make(chan struct{})
    go func() {
        logger.Info("in-flight worker task executing") // ✅ Correlated while request is active
        close(done)
    }()
    <-done
    w.WriteHeader(http.StatusOK)
})
```

---

### Python Runtime: The Block Buffering Trap & Asyncio Fixes

#### Why It FAILS Out of the Box: The `libc` Block Buffering Trap
By default, the C standard library (`libc`) detects whether standard output is connected to an interactive terminal (`isatty(fileno)`):
- **Terminal (TTY)**: Standard output is **line-buffered** (flushed on each newline `\n`).
- **Container Pipe (`/dev/stdout`)**: When running inside Docker or Kubernetes, stdout is redirected to a pipe. In non-TTY mode, Python switches to **block-buffering (typically 8,192 bytes)**.

As a result, Python buffers log lines in memory and only triggers the kernel `write()` syscall after 8 KiB accumulates. By that time, the original HTTP request has long since ended, and the thread is either idle or serving an unrelated request.

#### ❌ Broken Sample: Default Containerized Python
```python
# app.py - BROKEN IN CONTAINERS WITHOUT UNBUFFERED MODE
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

logging.basicConfig(level=logging.INFO, format='{"time":"%(asctime)s","msg":"%(message)s"}')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # ❌ FAILS: Log line stays in Python's internal 8 KiB buffer!
        # The write() syscall is NOT called during this request.
        logging.info("handling customer checkout")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK\n")

HTTPServer(("", 8082), Handler).serve_forever()
```

#### ✅ Working Fix 1 (Recommended Dockerfile): `ENV PYTHONUNBUFFERED=1`
As configured in [`demo-apps/python/Dockerfile`](../demo-apps/python/Dockerfile):
```dockerfile
FROM python:3.12-alpine
WORKDIR /app

# CRITICAL FOR OBI TRACE-LOG CORRELATION:
# Disables libc block buffering on pipes, ensuring each log write
# triggers an immediate write() syscall on the active thread.
ENV PYTHONUNBUFFERED=1

COPY app.py .
CMD ["python", "app.py"]
```

#### ✅ Working Fix 2 (CLI / Kubernetes Command Override)
Invoke Python with the `-u` (unbuffered) flag:
```bash
python -u app.py
```

#### ✅ Working Fix 3 (Code-Level Reconfiguration)
For existing applications where Dockerfiles cannot be modified, reconfigure standard streams in code:
```python
import sys
# Forces line buffering on stdout even when piped to a container runtime
sys.stdout.reconfigure(line_buffering=True)
```

#### ⚡ Asyncio & FastAPI Compatibility
In asynchronous frameworks (FastAPI, Starlette, AIOHTTP), OBI attaches uprobes to `_asyncio.Task.task_step` to update `traces_ctx_v1` across `await` yields:
```python
from fastapi import FastAPI
import logging, sys, asyncio

# Ensure synchronous stdout flushes
sys.stdout.reconfigure(line_buffering=True)
app = FastAPI()
logger = logging.getLogger("api")

@app.get("/items/{item_id}")
async def get_item(item_id: str):
    logger.info(f"fetching item {item_id}") # ✅ Correlated!
    await asyncio.sleep(0.05) # Yields execution to event loop
    logger.info(f"item {item_id} ready")    # ✅ Correlated after coroutine resume!
    return {"item_id": item_id}
```

---

### Node.js Runtime: Event Loop Alignment & Worker Thread Traps

#### Why It Works Out of the Box
Node.js processes requests on a single-threaded event loop. Standard `process.stdout.write` and `console.log` execute synchronous writes to file descriptor 1. OBI pairs an internal `async_hooks` bridge with a `uv_fs_access` dummy file descriptor probe to synchronize `traces_ctx_v1` as callbacks resume.

#### ✅ Working Sample: Direct Synchronous Stdout Stream
As implemented in [`demo-apps/nodejs/server.js`](../demo-apps/nodejs/server.js):
```javascript
const http = require('http');

function logJSON(level, msg, extra = {}) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    msg,
    ...extra
  }) + '\n';
  // Synchronous write on the main event-loop thread
  process.stdout.write(line);
}

const server = http.createServer((req, res) => {
  // ✅ Correlated: OBI intercepts this write() on the active HTTP context
  logJSON('INFO', 'handling node.js async transaction', { path: req.url });
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end('{"status":"ok"}\n');
});

server.listen(8083);
```

#### ❌ When It Fails: Asynchronous Worker-Thread Transports
Many Node.js teams configure **Pino** with multi-threaded worker transports (`pino.transport({ target: 'pino/file' })` or `thread-stream`) to offload log serialization from the main event loop.

```javascript
// ❌ BROKEN FOR OBI: Pino worker-thread transport
const pino = require('pino');

// Spins up a worker_threads worker to handle I/O asynchronously
const transport = pino.transport({
  target: 'pino/file',
  options: { destination: 1 } // Output to stdout via worker thread
});

const logger = pino(transport);

// In HTTP handler:
app.get('/order', (req, res) => {
  // ❌ FAILS: The main thread posts a message to the worker thread.
  // The worker thread executes the write() syscall. Because the worker thread
  // is detached from the HTTP request context, it has NO entry in traces_ctx_v1!
  logger.info('processing order');
  res.send('ok');
});
```

#### 💡 Remediation for Node.js
When deploying OBI, configure loggers to write synchronously to `process.stdout` on the main thread:
```javascript
// ✅ REMEDIATION: Direct stdout stream on the main thread
const pino = require('pino');
const logger = pino({
  level: 'info'
}, process.stdout); // Direct synchronous stream -> CORRELATED!
```

---

### Java Runtime: Platform Threads vs Project Loom Virtual Thread Failures

#### Platform Threads: Traditional Thread-Pool Servers (Works Out of the Box)
In standard Java architectures (Tomcat, Spring Boot, Jetty, Netty), incoming HTTP requests are served by dedicated platform threads (`catalina-exec-*`). OBI deploys a ByteBuddy bytecode agent that intercepts task submissions to `ThreadPoolExecutor` and calls a lightweight `ioctl` (`k_ioctl_java_threads`) to link parent and worker thread IDs in kernel space.

#### ✅ Working Sample: Java Microservice & Spring Boot
A complete runnable microservice is provided in [`demo-apps/java/`](../demo-apps/java/) (featuring [`App.java`](../demo-apps/java/App.java) and [`Dockerfile`](../demo-apps/java/Dockerfile)). Below is how enterprise Spring Boot with Logback or the standalone demo microservice executes on platform threads:

```java
@RestController
public class PaymentController {
    private static final Logger log = LoggerFactory.getLogger(PaymentController.class);

    @PostMapping("/payments")
    public ResponseEntity<String> processPayment(@RequestBody PaymentRequest req) {
        // ✅ Correlated: Executing on platform thread catalina-exec-1
        log.info("Processing payment for account={}", req.getAccountId());
        return ResponseEntity.ok("AUTHORIZED");
    }
}
```

#### ❌ When It Fails #1: Java 21+ Project Loom (Virtual Threads)
Project Loom decouples Java threads from operating system threads. A huge number of virtual threads (`java.lang.VirtualThread`) are multiplexed onto a small pool of carrier OS threads (`ForkJoinPool.commonPool()`):

```properties
# application.properties (Spring Boot 3.2+)
spring.threads.virtual.enabled=true # ❌ FAILS WITH OBI CORRELATION!
```

**Why Virtual Threads Break eBPF Kernel Correlation**:
1. When a virtual thread blocks on non-blocking socket I/O, it unmounts from its carrier OS thread.
2. When I/O completes, the virtual thread remounts on a potentially **different** carrier OS thread.
3. Crucially, multiple virtual threads run consecutively on the **same** carrier OS thread.
4. In the Linux kernel, `bpf_get_current_pid_tgid()` only sees the carrier OS thread's TID. The kernel cannot discern which user-space virtual thread is currently executing.
5. If virtual thread A sets a trace context in `traces_ctx_v1` on carrier thread 10, yields, and virtual thread B logs on carrier thread 10, **virtual thread B is falsely stamped with virtual thread A's trace ID** (severe trace cross-contamination).

#### 💡 Guidance for Project Loom
- **Option A (Recommended for OBI)**: Keep web request handling on standard platform thread pools (`server.tomcat.threads.max=200`).
- **Option B (In-Process Agent)**: If virtual threads are mandatory for throughput, deploy the official OpenTelemetry Java Agent (`-javaagent:opentelemetry-javaagent.jar`). The in-process agent tracks `ScopedValue` and virtual thread continuations in JVM memory until eBPF Loom support is engineered.

#### ❌ When It Fails #2: Asynchronous Log4j2 Disruptor Loggers
If Log4j2 is configured with the asynchronous LMAX Disruptor (`AsyncLogger`):
```properties
-Dlog4j2.contextSelector=org.apache.logging.log4j.core.async.AsyncLoggerContextSelector
```
Log events are placed into an in-memory ringbuffer and written by a single background thread (`Log4j2-AsyncLogger-1`). This background thread has no trace context in the kernel.

**Remediation**: Use standard synchronous console appenders with `immediateFlush="true"`:
```xml
<!-- log4j2.xml: Synchronous console appender -->
<Console name="Console" target="SYSTEM_OUT" immediateFlush="true">
  <JsonTemplateLayout eventTemplateUri="classpath:LogstashJsonEventLayoutV1.json"/>
</Console>
```

---

### .NET Runtime: ASP.NET Core Background Channel Dilemma & Solutions

#### Why It FAILS Out of the Box: The Background Channel Architecture
In .NET 6/7/8/9, standard console logging fails with OBI for two distinct reasons:
1. `Console.Out` is wrapped in a `StreamWriter` with `AutoFlush = false`, causing 4 KB block buffering.
2. The default ASP.NET Core console logger (`builder.Logging.AddConsole()`) queues log messages into an internal asynchronous queue (`System.Threading.Channels.Channel<LogMessageEntry>`). A single dedicated background writer thread (`ConsoleLoggerProcessor`) dequeues messages and performs the actual write syscall.

Because the writer thread is not the thread that executed the controller action, the kernel sees a `write()` syscall from a thread with zero trace context in `traces_ctx_v1`.

#### ❌ Broken Sample: Default ASP.NET Core `AddConsole()`
```csharp
// Program.cs - BROKEN FOR OBI CORRELATION
var builder = WebApplication.CreateBuilder(args);

// Default console provider delegates to an asynchronous background channel thread
builder.Logging.ClearProviders();
builder.Logging.AddConsole(); 

var app = builder.Build();

app.MapGet("/checkout", (ILogger<Program> logger) => {
    // ❌ FAILS: Log write occurs on background ConsoleLoggerProcessor thread!
    logger.LogInformation("Processing customer checkout");
    return Results.Ok(new { status = "approved" });
});

app.Run();
```

#### ✅ Working Fix 1 (Recommended: Serilog Synchronous Console)
A complete runnable microservice demonstrating both the broken out-of-the-box scenario and the synchronous fix is provided in [`demo-apps/dotnet/`](../demo-apps/dotnet/) (featuring [`Program.cs`](../demo-apps/dotnet/Program.cs), [`DotnetApp.csproj`](../demo-apps/dotnet/DotnetApp.csproj), and [`Dockerfile`](../demo-apps/dotnet/Dockerfile)).

Serilog's console sink writes synchronously on the calling thread:
```csharp
// Program.cs - FIXED FOR OBI CORRELATION
using Serilog;

// Configure Serilog to write synchronously to stdout on the calling thread
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console(new Serilog.Formatting.Json.JsonFormatter())
    .CreateLogger();

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseSerilog();

var app = builder.Build();

app.MapGet("/checkout", () => {
    // ✅ Correlated: write() syscall occurs synchronously on the request thread!
    Log.Information("Processing customer checkout");
    return Results.Ok(new { status = "approved" });
});

app.Run();
```

#### ✅ Working Fix 2: Native StreamWriter with `AutoFlush = true`
```csharp
// Force immediate stdout flushing on standard Console.Out
var stdout = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true };
Console.SetOut(stdout);
```

#### ✅ Working Fix 3: NLog Synchronous Console Target
Configure NLog without queueing:
```xml
<!-- nlog.config -->
<targets>
  <target xsi:type="Console" name="console" queueLimit="0" />
</targets>
```

---

### Ruby Runtime: Puma Reactor Paths & Background Job Limits

#### Why It Works Out of the Box
Puma servers dispatch HTTP requests from worker threads. OBI instruments `rb_ary_shift` (`Array#shift` in Ruby C internals) to synchronize `traces_ctx_v1` whenever a worker pulls a request from the reactor queue.

#### ✅ Working Sample: Puma Web Server
```ruby
# config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

# Ensure stdout stream is unbuffered
$stdout.sync = true
```

#### ⚠️ When It Does NOT Work: Asynchronous Background Workers
Asynchronous queue workers (Sidekiq, GoodJob, Resque) running in separate worker processes or threads do not share the HTTP thread's kernel context. Pass W3C `traceparent` headers inside the serialized job payload if asynchronous background jobs must correlate with originating HTTP requests.

---

### Plain-Text & Legacy Monoliths: Non-JSON Key-Value Enrichment

#### Universal Compatibility Without JSON
OBI does not require structured JSON logging. If a legacy C, C++, or Go application emits unstructured free-form log lines, OBI intercepts the `write()` system call, checks if the payload starts with `{`, and if not, automatically appends key-value annotations: `trace_id=<hex> span_id=<hex>`.

#### ✅ Working Sample: Legacy Unstructured Service
As implemented in [`demo-apps/plaintext/main.go`](../demo-apps/plaintext/main.go):
```go
package main

import (
    "fmt"
    "net/http"
    "time"
)

func main() {
    http.HandleFunc("/legacy", func(w http.ResponseWriter, r *http.Request) {
        // Raw unstructured string emitted to stdout
        fmt.Printf("[%s] legacy transaction executed user=john_doe status=ok\n", 
            time.Now().Format(time.RFC3339))
        w.Write([]byte("processed\n"))
    })

    http.ListenAndServe(":8084", nil)
}
```

#### Output Stream Result
```text
# Raw Application Output:
[2026-10-07T00:00:00Z] legacy transaction executed user=john_doe status=ok

# Enriched Output Captured by Container Engine:
[2026-10-07T00:00:00Z] legacy transaction executed user=john_doe status=ok trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=00f067aa0ba902b7
```

---

## 4. Deep Dive: Per-Runtime Kernel Refresh Mechanics

### Go Runtime: `runtime.casgstatus` Uprobes

Go implements zero-code correlation with zero configuration. It achieves this using a 3-part synchronization model:

```mermaid
sequenceDiagram
    autonumber
    participant Net as Net Poll / HTTP Uprobe
    participant G as Goroutine (G12)
    participant M as OS Thread (M1)
    participant BPF as BPF traces_ctx_v1 Map
    participant Sched as runtime.casgstatus Uprobe

    Net->>G: Inbound HTTP Request arrives
    Net->>BPF: Immediate set: obi_ctx__set(M1.pid_tgid, trace_id)
    G->>M: Executes handler code
    Note over G: Handler blocks on channel or network I/O
    Sched->>BPF: Transition out of _Grunning -> obi_ctx__del(M1.pid_tgid)
    Note over G: G12 resumes later on different thread M4
    Sched->>BPF: runtime.casgstatus(_Grunning / _Gsyscall on M4) -> obi_ctx__set(M4.pid_tgid, trace_id)
    G->>M: write() syscall executed on M4 -> CORRECT TRACE CONTEXT ENRICHED!
```

1. **Immediate Set at Uprobe Entry**: When an HTTP server handler (`ServeHTTP`, gRPC `server_handleStream`, etc.) starts, OBI immediately stores `(pid_tgid, trace_ctx)` in `traces_ctx_v1`. At this instant, the goroutine is guaranteed to run on the calling OS thread.
2. **Goroutine State Transitions**: The Go runtime calls `runtime.casgstatus` whenever a goroutine changes state. OBI attaches a uprobe here:
   - When transitioning to `_Grunning` (state 2) or `_Gsyscall` (state 3), OBI looks up the goroutine's active trace and calls `obi_ctx__set(current_pid_tgid, &tp)`.
   - Because `traces_ctx_v1` uses `BPF_ANY` hash semantics, updates are idempotent and race-free.
3. **Cleanup at Return**: When the handler completes, return uprobes delete the map entry via `obi_ctx__del(pid_tgid)`.

---

### Node.js Runtime: `async_hooks` & `uv_fs_access`

In Node.js, asynchronous callbacks execute sequentially on a single thread. Simply setting `traces_ctx_v1` on socket read would cause subsequent concurrent requests to overwrite each other before callbacks run.

OBI solves this with a lightweight user-space / kernel bridge:
1. The OBI Node.js agent registers an `async_hooks` hook:
   ```javascript
   const async_hooks = require('async_hooks');
   async_hooks.createHook({
     before(asyncId) {
       fs.accessSync(`/dev/null/obi-ctx/${incomingFd}`);
     }
   }).enable();
   ```
2. Calling `fs.accessSync` triggers a kernel syscall that hits OBI's `obi_uv_fs_access` uprobe.
3. The eBPF probe:
   - Parses the socket file descriptor from the dummy file path.
   - Looks up `fd_to_connection[pid_tgid, fd]` in kernel memory.
   - Refreshes `traces_ctx_v1[pid_tgid]` with the matching request's trace context.
4. When the JavaScript callback runs and calls `console.log()` or `pino.info()`, `traces_ctx_v1` is perfectly synchronized.

---

### Java Runtime: ByteBuddy & Thread Hierarchy `ioctl`

Java enterprise workloads (Spring Boot, Tomcat, Jetty, Netty) dispatch incoming requests from network selector threads to worker thread pools (`ThreadPoolExecutor`, `ForkJoinPool`).

1. **ByteBuddy Bytecode Instrumentation**:
   - The OBI Java helper instruments `Executor.execute()`, `Runnable.run()`, `Callable.call()`, and `ForkJoinTask`.
2. **Kernel Notification via `ioctl`**:
   - When a task begins execution on a worker thread, it issues an `ioctl` call:
     ```c
     ioctl(0, 0x0b10b1, packet); // Operation: k_ioctl_java_threads (3)
     ```
3. **Hierarchy Traversal in eBPF**:
   - The BPF kprobe intercepts `sys_ioctl`.
   - It maintains a `java_tasks[child_tid] = parent_tid` hierarchy map.
   - It traverses up to 3 levels of ancestor threads to locate the original `server_traces` context.
   - It populates `traces_ctx_v1[child_pid_tgid]` with the parent's trace context.
4. **Project Loom (Virtual Threads) Limitation**:
   > [!WARNING]
   > Virtual threads jump across JVM carrier threads dynamically. In kernel space, `bpf_get_current_pid_tgid()` only sees the carrier OS thread. If two virtual threads share a carrier thread, stamping the carrier thread in `traces_ctx_v1` would cause trace pollution. Virtual threads are therefore not currently enriched.

---

### Ruby (Puma): Direct vs Reactor Path (`rb_ary_shift`)

Puma uses two request processing models:
- **Direct Path**: A Puma worker thread reads socket data directly. `server_or_client_trace()` sets `traces_ctx_v1` immediately on the worker thread.
- **Reactor Path**: Under heavy load, a separate reactor thread reads HTTP data, then places work into Puma's `todo` queue.
- **The Fix**: OBI hooks `rb_ary_shift` (`Array#shift` in Ruby C internals), which fires whenever a worker thread pulls a request from the queue. The BPF handler maps `puma_worker_tasks[worker_tid] = reactor_tid` and synchronizes the trace context.

---

### Python Runtime: CPython Asyncio & `PYTHONUNBUFFERED=1`

Python presents two critical challenges: C standard library stdout block buffering and `asyncio` task switching.

#### 1. The Block Buffering Trap
By default, the C runtime library (`libc`) checks whether `stdout` is a terminal (TTY).
- If attached to a TTY: `stdout` is line-buffered.
- If attached to a container pipe (`/dev/stdout`): `stdout` is **block-buffered** (8 KiB buffer).
- Result without configuration: Python holds log lines in memory and only calls `write()` when 8 KiB accumulates. By that time, the HTTP request has finished and the thread is handling another request or is idle!
- **Mandatory Dockerfile Setting**:
  ```dockerfile
  ENV PYTHONUNBUFFERED=1
  ```
  This forces Python's standard streams to write directly to the kernel without libc buffering.

#### 2. Asyncio Task Switching Probes
OBI attaches uprobes to CPython internals:
- `_asyncio.Task.__init__`: Tracks new tasks and parentage.
- `_asyncio.Task.task_step` (Python 3.12+) / `task_step_legacy` (< 3.12): Fires whenever the event loop resumes an async coroutine. The probe updates `traces_ctx_v1` with the task's context.
- `task_step_ret`: Fires when a task yields (`await`). Deletes `traces_ctx_v1` so idle loop code does not carry stale IDs.
- `libpython3.context_run`: Covers worker threads launched via `asyncio.to_thread()`.

---

### .NET Runtime: Synchronous Writers vs Background Channels

In .NET Core / .NET 8+, `Console.Out` is wrapped by a `StreamWriter` configured with `AutoFlush = false`.

#### The Background Channel Problem
The default ASP.NET Core console logger (`Microsoft.Extensions.Logging.Console` via `builder.Logging.AddConsole()`) queues log messages into an internal asynchronous `System.Threading.Channels.Channel`. A single dedicated background writer thread dequeues and writes to stdout.
- Because the writer thread is **not** the thread that executed the controller action, it has no trace context in `traces_ctx_v1`.
- `AddConsole()` **will not correlate logs with OBI**.

#### Supported Solutions in .NET
Use synchronous console appenders:
1. **Direct `StreamWriter` with `AutoFlush`**:
   ```csharp
   var stdout = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true };
   Console.SetOut(stdout);
   ```
2. **Serilog Console**:
   ```csharp
   Log.Logger = new LoggerConfiguration()
       .WriteTo.Console() // Writes synchronously on calling thread
       .CreateLogger();
   ```
3. **NLog ColoredConsole**:
   ```xml
   <target name="console" xsi:type="ColoredConsole" queueLimit="0" />
   ```

---

## 5. Coexistence with OpenTelemetry In-Process SDKs (Hybrid Mode)

In enterprise migrations, many applications already export traces via the official OpenTelemetry SDK (e.g., `opentelemetry-go`, `opentelemetry-java`), but have not configured log correlation.

```text
[HTTP Request] ---> App with OTel Tracing SDK
                        │
                        ├── Emits Span (TraceID: AAAA, SpanID: BBBB) -> OTLP Exporter
                        │
                        └── Emits Log to stdout: {"msg":"user login"} (NO trace context)
```

OBI automatically identifies when a process is already exporting OTLP traces.
- **Trace ID Injection**: OBI injects `trace_id` (`AAAA`) to link logs with the distributed trace.
- **Span ID Suppression**: OBI **does not inject `span_id`**. OBI's kernel probe would otherwise generate its own synthetic span ID (`CCCC`), which would conflict with the SDK's actual child span (`BBBB`).
- By injecting only `trace_id`, OBI maintains full trace-to-log navigability without creating contradictory span relationships in APM backends.


---

## 🧭 Navigation & Documentation Directory

| ⬅️ Previous Document | 🏠 Documentation Hub | ➡️ Next Document |
| :--- | :---: | ---: |
| [**Log Shipper Filtering Guide**](log-filtering-guide.md) | [**Repository Overview**](../README.md) | [**Troubleshooting & Diagnostics**](troubleshooting.md) |

### 📚 Complete Guide Catalog
- 📜 **[Official Reference Announcement](reference-blog-announcement.md)** — Verbatim OpenTelemetry announcement with junior primers and kernel deep dives
- 🏛️ **[Architecture Deep Dive](architecture.md)** — Low-level syscall hooks (`pipe_write`, `ksys_write`, `do_writev`), LRU maps, and ringbuffer flow
- 📋 **[Day 0: Planning & Sizing](day0-planning-sizing.md)** — Linux 6.0+ matrix, kernel lockdown, memory sizing formulas, and security postures
- 📦 **[Day 1: Multi-Cluster Deployment](day1-installation.md)** — Enterprise overlays for OpenShift 4.20+, AKS, EKS, GKE, RKE2, and Docker Compose
- 🚨 **[Day 2: Operations & Incident Triage](day2-operations-triage.md)** — SRE incident response playbook, LogQL/Jaeger queries, and canary rollouts
- 💧 **[Log Shipper Filtering Guide](log-filtering-guide.md)** — Suppressed NUL byte placeholder drop filters and 8 KiB write split handling
- ⚡ **[Runtime Compatibility Guide](runtime-compatibility.md)** — Go runtime hooks, `PYTHONUNBUFFERED=1`, Node.js async streams, and Java Loom
- 🔧 **[Troubleshooting & Diagnostics](troubleshooting.md)** — Common pitfalls, eBPF probe errors, missing trace IDs, and verification steps
- 🧹 **[Decommission & Teardown Guide](decommission-guide.md)** — Safe probe detachment, BPF map unpinning, and resource cleanup
- 📚 **[References & Official Documentation](references.md)** — Upstream OpenTelemetry specifications, GitHub repositories, and CNCF channels
