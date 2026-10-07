# Java Microservice: Zero-Code Trace-Log Correlation Demo

This service demonstrates how OpenTelemetry eBPF Instrumentation (OBI) correlates standard Java `stdout` logs with distributed traces without requiring OpenTelemetry SDK dependencies.

## Key Architectural Concepts

### 1. Platform Threads (Default: `USE_VIRTUAL_THREADS=false`)
- **Works Out of the Box**: Standard Java application servers (Tomcat, Netty, Jetty, Spring Boot) dispatch requests to dedicated platform threads (`catalina-exec-*`).
- **Kernel Interception**: OBI attaches ByteBuddy bytecode instrumentation to thread submission points (`ThreadPoolExecutor`) and uses an `ioctl` hook (`k_ioctl_java_threads`) to link worker threads with parent HTTP request traces in `traces_ctx_v1`.
- **Immediate Flush**: `System.out.print` directly invokes the `write()` system call on the active OS thread.

### 2. Project Loom Virtual Threads (Toggle: `USE_VIRTUAL_THREADS=true`)
- **Why It Fails**: In Java 21+, virtual threads (`java.lang.VirtualThread`) are user-space fibers scheduled onto a small pool of carrier OS threads (`ForkJoinPool.commonPool()`).
- **Kernel Limitation**: The Linux kernel eBPF probe only sees the carrier OS thread's TID via `bpf_get_current_pid_tgid()`. When multiple virtual threads run consecutively on the same carrier thread, trace context collides, resulting in severe cross-request trace pollution.
- **Production Guidance**: For OBI zero-code correlation, retain platform thread pools or use the official in-process Java Agent (`-javaagent:opentelemetry-javaagent.jar`).

## Endpoints

- `GET /healthz`: Health check returning `200 OK`.
- `POST /payments`: Simulates payment transaction logging structured JSON to stdout.

## Running Locally with Docker

```bash
# Build the image
docker build -t obi-demo-java demo-apps/java/

# Run with Platform Threads (Compatible with OBI)
docker run -p 8085:8085 -e USE_VIRTUAL_THREADS=false obi-demo-java

# Test endpoint
curl -X POST http://localhost:8085/payments
```
