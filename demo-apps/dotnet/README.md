# .NET Microservice: Zero-Code Trace-Log Correlation Demo

This service demonstrates how OpenTelemetry eBPF Instrumentation (OBI) correlates .NET (C#) application logs with distributed traces, and highlights why standard ASP.NET Core console logging fails without explicit configuration.

## Key Architectural Concepts

### 1. Why Default ASP.NET Core Fails (`USE_SYNCHRONOUS_LOGGER=false`)
- **The Background Channel Problem**: The default ASP.NET Core console logger (`builder.Logging.AddConsole()`) uses `ConsoleLoggerProvider`, which queues log entries into an internal thread-safe `System.Threading.Channels.Channel<LogMessageEntry>`.
- **Decoupled Worker Thread**: A single dedicated background writer thread (`ConsoleLoggerProcessor`) dequeues messages and executes `write()` syscalls to stdout.
- **Lost eBPF Context**: The background writer thread is **not** the thread that executed the controller action. The Linux kernel eBPF probe checks `bpf_get_current_pid_tgid()`, finds no active trace context for the background thread, and leaves the log line unenriched.
- **StreamWriter Buffering**: In addition, `Console.Out` wraps stdout in a `StreamWriter` with `AutoFlush = false`, causing 4 KB block buffering.

### 2. The Solution (`USE_SYNCHRONOUS_LOGGER=true`, Default)
- **Serilog Synchronous Console**: Serilog's console sink writes synchronously on the calling thread. The `write()` syscall occurs inside the controller execution context, enabling OBI to capture and inject matching `trace_id` and `span_id`.
- **Alternative Native Fix**: Setting `Console.SetOut(new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true })`.

## Endpoints

- `GET /healthz`: Health check returning `200 OK`.
- `GET /checkout`: Simulates order processing and logs structured JSON.

## Running Locally with Docker

```bash
# Build the image
docker build -t obi-demo-dotnet demo-apps/dotnet/

# Run with Synchronous Logging (Compatible with OBI)
docker run -p 8086:8086 -e USE_SYNCHRONOUS_LOGGER=true obi-demo-dotnet

# Run with Asynchronous Logging (Demonstrates Missing Trace IDs)
docker run -p 8086:8086 -e USE_SYNCHRONOUS_LOGGER=false obi-demo-dotnet

# Test endpoint
curl http://localhost:8086/checkout
```
